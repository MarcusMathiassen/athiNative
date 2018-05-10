//
//  ParticleSystemUberShader.metal
//  Athi
//
//  Created by Marcus Mathiassen on 07/05/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

// ---------Name qualifers---------------
//     fc_*:   Function constant
//     fc_uses_*: If a buffer is used or not
//     fc_has_*:  If a feature is enabled
// -------------------------

#include <metal_stdlib>
using namespace metal;

#include "ShaderTypes.h"
#include "UtilityFunctions.h" // rand2, homingMissile, attracted_to_point, collision_check, collision_resolve

// ----------Function constants---------------
constant bool fc_has_borderBound         [[function_constant(0)]];
constant bool fc_has_drawToTexture       [[function_constant(1)]];
constant bool fc_has_intercollision      [[function_constant(2)]];
constant bool fc_has_lifetime            [[function_constant(3)]];
constant bool fc_has_attractedToMouse    [[function_constant(4)]];
constant bool fc_has_homing              [[function_constant(5)]];
constant bool fc_has_turbulence          [[function_constant(6)]];
constant bool fc_has_canAddParticles     [[function_constant(7)]];

constant bool fc_uses_radii     = true;
constant bool fc_uses_masses    = fc_has_intercollision || fc_has_attractedToMouse;

constant bool fc_uses_texture   = fc_has_drawToTexture;
constant bool fc_uses_colors    = true;

constant bool fc_uses_isAlives  = fc_has_lifetime;
constant bool fc_uses_lifetimes = fc_has_lifetime;

constant bool fc_uses_seed_buffer = fc_has_turbulence;
constant bool fc_uses_field_nodes = fc_has_turbulence;
// -------------------------


kernel
void init_buffers(
                  device _Emitter*  emitters                 [[ buffer(bf_emitters_index) ]],
                  device uint16_t*   emitter_indices          [[ buffer(bf_emitter_indices_index) ]],

                  device float2*   positions                [[ buffer(bf_positions_index) ]],
                  device float2*   velocities               [[ buffer(bf_velocities_index) ]],

                  device float*   radii      [[ buffer(bf_radii_index), function_constant(fc_uses_radii) ]],
                  device float*   masses     [[ buffer(bf_masses_index), function_constant(fc_uses_masses) ]],
                  device float4*  colors     [[ buffer(bf_colors_index), function_constant(fc_uses_colors) ]],
                  device bool*    isAlives   [[ buffer(bf_isAlives_index), function_constant(fc_uses_isAlives) ]],
                  device float*   lifetimes  [[ buffer(bf_lifetimes_index), function_constant(fc_uses_lifetimes) ]],

                  //----------------------------------
                  //  Turbulence
                  //----------------------------------
                  device int32_t* seed_buffer [[ buffer(bf_seed_buffer_index), function_constant(fc_uses_seed_buffer) ]],
                  device float2* field_nodes [[ buffer(bf_field_nodes_index), function_constant(fc_uses_field_nodes) ]],
                  //----------------------------------
                  constant SimParam&     simParam     [[ buffer(bf_simParam_index) ]],

                  uint particleIndex [[ thread_position_in_grid ]]
                  )
{
    thread const auto index = particleIndex;

    //----------------------------------
    //  Initilize all particle buffers
    //----------------------------------

    // Get the emitter for this particle
    thread auto emitter = emitters[emitter_indices[index]];

    const auto dir = emitter.direction * emitter.speed;

    positions[index] = emitter.position;
    velocities[index] = dir + rand2(-emitter.spread, emitter.spread, index, emitter.particle_count/3, 34);

    if (fc_uses_radii)      radii[index] = emitter.size;
    if (fc_uses_masses)     masses[index] = M_PI_F * emitter.size * emitter.size;
    if (fc_uses_colors)     colors[index] = emitter.color;
    if (fc_uses_isAlives)   isAlives[index] = true;
    if (fc_uses_lifetimes)  lifetimes[index] = emitter.lifetime * rand(index, index*34 / index, 34);
}

kernel
void uber_compute(

  device _Emitter*  emitters                    [[ buffer(bf_emitters_index) ]],
  device uint16_t*   emitter_indices              [[ buffer(bf_emitter_indices_index) ]],

  device float2*   positions                    [[ buffer(bf_positions_index) ]],
  device float2*   velocities                   [[ buffer(bf_velocities_index) ]],

  device uint32_t&     gpuParticleCount             [[ buffer(bf_gpuParticleCount_index) ]],

  device float*   radii      [[ buffer(bf_radii_index), function_constant(fc_uses_radii) ]],
  device float*   masses     [[ buffer(bf_masses_index), function_constant(fc_uses_masses) ]],
  device float4*  colors     [[ buffer(bf_colors_index), function_constant(fc_uses_colors) ]],
  device bool*    isAlives   [[ buffer(bf_isAlives_index), function_constant(fc_uses_isAlives) ]],
  device float*   lifetimes  [[ buffer(bf_lifetimes_index), function_constant(fc_uses_lifetimes) ]],


  //----------------------------------
  //  Turbulence
  //----------------------------------
  device int32_t* seed_buffer [[ buffer(bf_seed_buffer_index), function_constant(fc_uses_seed_buffer) ]],
  device float2* field_nodes [[ buffer(bf_field_nodes_index), function_constant(fc_uses_field_nodes) ]],
  //----------------------------------

  constant MotionParam&  motionParam  [[ buffer(bf_motionParam_index) ]],
  constant SimParam&     simParam     [[ buffer(bf_simParam_index) ]],

  uint particleIndex [[ thread_position_in_grid ]],

  texture2d<float, access::write>  texture  [[ texture(0), function_constant(fc_uses_texture) ]]
)
{
    //----------------------------------
    //  Local variables
    //----------------------------------

    thread const auto index = particleIndex;

    // Get the emitter for this particle
    const auto emitter_id = emitter_indices[index];
    const auto emitter = emitters[emitter_id];
    thread const auto is_first_thread = index == 0 ? true : false;
    
    if (is_first_thread && simParam.emitter_count != gpuParticleCount)
    {
        uint32_t counter = emitters[gpuParticleCount].start_index;
        // Find emitter for this particle
        for (uint32_t emitter_index = gpuParticleCount;
             emitter_index < simParam.emitter_count; ++emitter_index)
        {
            const auto amount = emitters[emitter_index].start_index + emitters[emitter_index].particle_count;
            for (uint32_t i = counter; i < amount; ++i)
            {
                emitter_indices[i] = emitter_index;
            }
            counter += amount;
        }
        gpuParticleCount = simParam.emitter_count;
    }
//    thread const auto is_first_thread = (index == emitter.start_index) ? true : false;

    //----------------------------------
    //  Runs once each frame
    //----------------------------------
//    if (fc_has_canAddParticles)
//    {
//        if (emitter.has_can_add_particles)
//        {
////            //----------------------------------
////            //  Adds a particle using
////            //----------------------------------
////            if (is_first_thread && simParam.shouldAddParticle && emitter_id == simParam.selected_emitter_id)
////            {
////                // Each new particle gets the same position but different velocities
////                const uint32_t amount = simParam.add_particles_count;
////
////                for (uint newIndex = emitter.start_index + emitter.particle_count; newIndex < amount; ++newIndex)
////                {
////                    positions[newIndex] = emitter.position;
////                    velocities[newIndex] = emitter.speed * emitter.direction;
////
////                    if (fc_uses_radii)      radii[newIndex] = emitter.size;
////                    if (fc_uses_masses)     masses[newIndex] = M_PI_F * emitter.size * emitter.size;
////                    if (fc_uses_colors)     colors[newIndex] = emitter.color;
////                    if (fc_uses_isAlives)   isAlives[newIndex] = true;
////                    if (fc_uses_lifetimes)  lifetimes[newIndex] = emitter.lifetime * rand(index, index*34 / index, 34);
////                }
////                emitters[emitter_id].particle_count += amount;
////            }
//        }
//    }

    auto  pos         = positions[index];
    auto  vel         = velocities[index];

    auto  color       = colors[index];
    auto  radius      = radii[index];

    auto  mass        = masses[index];
    auto  isAlive     = isAlives[index];
    auto  lifetime    = lifetimes[index];

    threadgroup_barrier(mem_flags::mem_device);

    if (fc_has_turbulence)
    {
        const int scale = 5;
        const auto ppos = to_viewspace(pos, simParam.viewportSize);
        int x = floor(ppos.x / scale);
        int y = floor(ppos.y / scale);
        x = (x < 0) ? 0 : x;
        y = (y < 0) ? 0 : y;
        const int iii = x + y * simParam.viewportSize.x;
        vel += field_nodes[iii];
    }

    if (fc_has_lifetime)
    {
        //----------------------------------
        //  hasLifetime
        //----------------------------------

        if (emitter.has_lifetime)
        {
            // Decrease the lifetime
            lifetime -= motionParam.deltaTime;

            // If the lifetime of this particle has come to an end. Dont update it, dont draw it.
            if (lifetime < 0)
            {
                isAlive = false;
            }

            // Fade the particle out until it's dead
            if (fc_uses_colors)
            {
                color = float4(color.rgb, lifetime);
            }

            // Respawn the particle if dead
            if (!isAlive)
            {
                const auto dir = emitter.direction * emitter.speed;

                pos = emitter.position;
                vel = dir + rand2(-emitter.spread, emitter.spread, index, emitter.particle_count/3, index*index);

                if (fc_uses_radii)      radius = emitter.size;
                if (fc_uses_masses)     mass = M_PI_F * emitter.size * emitter.size;
                if (fc_uses_colors)     color = emitter.color;
                if (fc_uses_isAlives)   isAlive = true;
                if (fc_uses_lifetimes)  lifetime = emitter.lifetime * rand(index, index*34 / index, 34);
            }
        }
    }

    if (fc_has_homing)
    {
        if (emitter.has_homing)
        {
            vel = homingMissile(emitter.target_pos, 1.0, pos, vel);
        }
    }

    if (fc_has_attractedToMouse)
    {
        vel = attract_to_point(simParam.mousePos, pos, vel, mass);
    }

    if (fc_has_intercollision)
    {
        if (emitter.has_intercollision)
        {
            //----------------------------------
            //  interCollision
            //  uses: positions, velocities, radii, masses, simParam,
            //----------------------------------

            for (uint32_t otherIndex = 0; otherIndex < simParam.particleCount; ++otherIndex)
            {
                if (index == otherIndex) { continue; }

                if (fc_uses_isAlives)
                {
                    if (!isAlives[otherIndex]) { continue; }
                }

                // Skip any emitters without collision
                const auto other_emitter = emitters[emitter_indices[otherIndex]];
                if (!other_emitter.has_intercollision) {
                    otherIndex = other_emitter.end_index;
                }

                const auto other_pos = positions[otherIndex];
                const auto other_radi = radii[otherIndex];

                if (collision_check(pos, other_pos, radius, other_radi))
                {
                    const auto other_vel = velocities[otherIndex];
                    const auto other_mass = masses[otherIndex];

                    vel = collision_resolve(pos, vel, mass, other_pos, other_vel, other_mass);
                }
            }
        }
    }

    if (fc_has_borderBound)
    {
        if (emitter.has_borderbound)
        {
            //----------------------------------
            //  borderBound
            //  uses: radius
            //----------------------------------
            if (pos.x < 0 + radius)                        { pos.x = radius;                              vel.x *= -1; }
            if (pos.x > simParam.viewportSize.x - radius)  { pos.x = simParam.viewportSize.x - radius;    vel.x *= -1; }
            if (pos.y < 0 + radius)                        { pos.y = radius;                              vel.y *= -1; }
            if (pos.y > simParam.viewportSize.y - radius)  { pos.y = simParam.viewportSize.y - radius;    vel.y *= -1; }
        }
    }

    if (fc_has_drawToTexture)
    {
        //----------------------------------
        // uses: positions, colors, simParam, texture
        //----------------------------------
        if (pos.x > 0 && pos.x < simParam.viewportSize.x &&
            pos.y > 0 && pos.y < simParam.viewportSize.y)
        {
            const auto fpos = ushort2(pos.x, simParam.viewportSize.y - pos.y);
            texture.write(color, fpos);
        }
    }

    {
        threadgroup_barrier(mem_flags::mem_device);
        //----------------------------------
        //  Update
        //  uses: positions, velocities, simParam, gpuParticleCount,
        //----------------------------------

        // Update all used variables
        velocities[index] = vel + emitter.gravity_force;
        positions[index] = pos + velocities[index];

        if (fc_uses_radii)      radii[index] = radius;
        if (fc_uses_masses)     masses[index] = mass;
        if (fc_uses_colors)     colors[index] = color;
        if (fc_uses_isAlives)   isAlives[index] = isAlive;
        if (fc_uses_lifetimes)  lifetimes[index] = lifetime;
    }

}


struct VertexOut
{
    vector_float4 position[[position]];
    vector_float4 color;
};


vertex
VertexOut particle_vert(
          constant float2*     positions       [[ buffer(bf_positions_index) ]],
          constant float*      radii           [[ buffer(bf_radii_index) ]],
          constant float4*     colors          [[ buffer(bf_colors_index) ]],
          constant float2*     vertices        [[ buffer(bf_vertices_index) ]],
          constant float*      lifetimes       [[ buffer(bf_lifetimes_index), function_constant(fc_uses_lifetimes) ]],
          constant float2&     viewport_size   [[ buffer(bf_viewportSize_index) ]],
          uint vid                             [[ vertex_id ]],
          uint iid                             [[ instance_id ]]
)
{
    // We shift the position by -1.0 on both x and y axis because of metals viewspace coords
    const float2 fpos = -1.0 + (radii[iid] * vertices[vid] + positions[iid]) / (viewport_size / 2.0);

    VertexOut vOut;
    vOut.position = float4(fpos, 0, 1);
    vOut.color = colors[iid];

    // Fade out based on lifetime
    if (fc_has_lifetime)
    {
        vOut.color.a = lifetimes[iid];
    } else {
        vOut.color.a = 0.5;
    }

    return vOut;
}

struct FragmentOut
{
    vector_float4 color0[[color(0)]];
    vector_float4 color1[[color(1)]];
};

fragment
FragmentOut particle_frag(VertexOut vert [[stage_in]])
{
    return { vert.color, vert.color };
}

