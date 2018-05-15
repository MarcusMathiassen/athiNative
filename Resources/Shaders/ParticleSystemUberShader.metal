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
constant bool fc_has_respawns            [[function_constant(8)]];

constant bool fc_uses_radii     = true;
constant bool fc_uses_masses    = fc_has_intercollision || fc_has_attractedToMouse;

constant bool fc_uses_texture   = fc_has_drawToTexture;
constant bool fc_uses_colors    = true;

constant bool fc_uses_isAlives  = fc_has_lifetime;
constant bool fc_uses_lifetimes = fc_has_lifetime;
// -------------------------

struct Emitter
{
    bool isActive;
    float2 position;
    float2 direction;
    float size;
    float speed;
    float lifetime;
    float spread;
    half4 color;
    uint particleCount;
    uint startIndex;
    
    bool hasHoming;
    bool hasLifetime;
    bool hasBorderBound;
    bool hasIntercollision;
    bool hasCanAddParticles;
    bool hasRespawns;
};

kernel
void basic_update(device Emitter*  emitters [[ buffer(bf_emitters_index) ]],
                  device ushort*   emitter_indices [[ buffer(bf_emitter_indices_index) ]],

                  device float2*   positions   [[ buffer(bf_positions_index) ]],
                  device float2*   velocities  [[ buffer(bf_velocities_index) ]],

                  device float*   radii        [[ buffer(bf_radii_index) ]],
                  device half4*  colors       [[ buffer(bf_colors_index) ]],

                  device bool*    isAlives     [[ buffer(bf_isAlives_index) ]],
                  device float*   lifetimes    [[ buffer(bf_lifetimes_index) ]],

                  device float*   masses  [[ buffer(bf_masses_index), function_constant(fc_uses_masses) ]],
                  
                  constant GlobalParam&  globalParam [[buffer(bf_globalParam_index)]],

                  const uint index [[ thread_position_in_grid ]]
)
{
    if (lifetimes[index] < 0)
    {
        // Get the emitter for this particle
        const auto emitter = emitters[emitter_indices[index]];

        const auto vel = emitter.direction * emitter.speed;

        positions[index] = emitter.position;
        velocities[index] = vel + rand2(-emitter.spread, emitter.spread, index);


        // Update variables if available
        radii[index] = emitter.size * 0.5 + emitter.size * rand_f32(0.0, 0.5, globalParam.seed * index);
        colors[index] = emitter.color;
        isAlives[index] = true;

        const auto particleIndexInEmitter = index - emitter.startIndex;
        lifetimes[index] = emitter.lifetime * rand_f32(0, 1, globalParam.seed * particleIndexInEmitter);
        if (fc_uses_masses)  masses[index] = M_PI_F * emitter.size * emitter.size;

    } else {
        // Decrease the lifetime
        lifetimes[index] -= globalParam.deltaTime;

        // Fade the particle out until it's dead
        if (fc_uses_colors)
        {
//            colors[index].a = lifetimes[index];
        }
    }
    
    velocities[index] += globalParam.gravityForce;
    positions[index] += velocities[index];
}
//
//kernel
//void uber_compute(
//
//  device Emitter*  emitters [[ buffer(bf_emitters_index) ]],
//  device ushort*   emitter_indices [[ buffer(bf_emitter_indices_index) ]],
//
//  device float2*   positions [[ buffer(bf_positions_index) ]],
//  device float2*   velocities [[ buffer(bf_velocities_index) ]],
//
//  device uint&     gpuParticleCount [[ buffer(bf_gpuParticleCount_index) ]],
//
//  device float*   radii      [[ buffer(bf_radii_index), function_constant(fc_uses_radii) ]],
//  device float*   masses     [[ buffer(bf_masses_index), function_constant(fc_uses_masses) ]],
//  device float4*  colors     [[ buffer(bf_colors_index), function_constant(fc_uses_colors) ]],
//  device bool*    isAlives   [[ buffer(bf_isAlives_index), ]],
//  device float*   lifetimes  [[ buffer(bf_lifetimes_index) ]],
//  //----------------------------------
//
//  constant MotionParam&  motionParam  [[ buffer(bf_motionParam_index) ]],
//  constant SimParam&     simParam     [[ buffer(bf_simParam_index) ]],
//
//  const uint index [[ thread_position_in_grid ]],
//
//  texture2d<float, access::write>  texture  [[ texture(0), function_constant(fc_uses_texture) ]]
//)
//{
//    // Get the emitter for this particle
//    const auto emitter_id = emitter_indices[index];
//    const auto emitter = emitters[emitter_id];
//
//    if (fc_has_lifetime)
//    {
//        if (emitter.hasLifetime)
//        {
//            // Respawn the particle if dead
////            if (fc_has_respawns)
////            {
////                if (emitter.hasRespawns)
////                {
//                    if (lifetimes[index] < 0)
//                    {
//                        const auto dir = emitter.direction * emitter.speed;
//
//                        positions[index] = emitter.position;
//
//                        const Range<float> spread_range = {-emitter.spread, emitter.spread};
//                        const Seed seed = {static_cast<int>(index), static_cast<int>(emitter.particleCount/3), 34};
//                        velocities[index] = dir + rand2(spread_range, seed);
//
//                        if (fc_uses_radii)      radii[index] = emitter.size;
//                        if (fc_uses_masses)     masses[index] = M_PI_F * emitter.size * emitter.size;
//                        if (fc_uses_colors)     colors[index] = emitter.color;
//                        if (fc_uses_isAlives)   isAlives[index] = true;
//                        if (fc_uses_lifetimes)  lifetimes[index] = emitter.lifetime * rand({static_cast<int>(index), static_cast<int>(index-34 * index), 34});
//                    }
//                    else
//                    {
//                        // Decrease the lifetime
//                        lifetimes[index] -= motionParam.deltaTime;
//
//                        // Fade the particle out until it's dead
//                        if (fc_uses_colors)
//                        {
//                            colors[index].a = lifetimes[index];
//                        }
////                    }
////                }
//            }
//        }
//    }
//
//    auto  pos = positions[index];
//    auto  vel = velocities[index];
//
//    auto  color = colors[index];
//    auto  radius = radii[index];
//
//    auto  mass = masses[index];
//    auto  isAlive = isAlives[index];
//    auto  lifetime = lifetimes[index];
//
//    threadgroup_barrier(mem_flags::mem_device);
//
//    if (fc_has_homing)
//    {
//        if (emitter.hasHoming)
//        {
//            vel = homingMissile(simParam.attractPoint, 1.0, pos, vel);
//        }
//    }
//
//    if (fc_has_attractedToMouse)
//    {
//        vel = attract_to_point(simParam.mousePos, pos, vel, mass);
//    }
//
//    if (fc_has_intercollision)
//    {
//        if (emitter.hasIntercollision)
//        {
//            for (uint otherIndex = 0; otherIndex < simParam.particleCount; ++otherIndex)
//            {
//                if (index == otherIndex) { continue; }
//
//                if (fc_uses_isAlives)
//                {
//                    if (!isAlives[otherIndex]) { continue; }
//                }
//
//                // Skip any emitters without collision
//                const auto other_emitter = emitters[emitter_indices[otherIndex]];
//                if (!other_emitter.hasIntercollision)
//                {
//                    otherIndex = other_emitter.startIndex + other_emitter.particleCount;
//                }
//
//                const auto other_pos = positions[otherIndex];
//                const auto other_radi = radii[otherIndex];
//
//                if (collision_check(pos, other_pos, radius, other_radi))
//                {
//                    const auto other_vel = velocities[otherIndex];
//                    const auto other_mass = masses[otherIndex];
//
//                    vel = collision_resolve(pos, vel, mass, other_pos, other_vel, other_mass);
//                }
//            }
//        }
//    }
//
//    if (fc_has_borderBound)
//    {
//        if (emitter.hasBorderBound)
//        {
//            if (pos.x < 0 + radius)                        {  vel.x *= -1; }
//            if (pos.x > simParam.viewportSize.x - radius)  {  vel.x *= -1; }
//            if (pos.y < 0 + radius)                        {  vel.y *= -1; }
//            if (pos.y > simParam.viewportSize.y - radius)  {  vel.y *= -1; }
//        }
//    }
//
//    if (fc_has_drawToTexture)
//    {
//        if (pos.x > 0 && pos.x < simParam.viewportSize.x &&
//            pos.y > 0 && pos.y < simParam.viewportSize.y)
//        {
//            const auto fpos = ushort2(pos.x, simParam.viewportSize.y - pos.y);
//            texture.write(color, fpos);
//        }
//    }
//
//    {
//        threadgroup_barrier(mem_flags::mem_device);
//
//        // Update all used variables
//        vel += simParam.gravityForce;
//
//        velocities[index] = vel;
//        positions[index] = pos + vel;
//
//        if (fc_uses_radii)      radii[index] = radius;
//        if (fc_uses_masses)     masses[index] = mass;
//        if (fc_uses_colors)     colors[index] = color;
//        if (fc_uses_isAlives)   isAlives[index] = isAlive;
//        if (fc_uses_lifetimes)  lifetimes[index] = lifetime;
//    }
//}

struct VertexOut
{
    float4 position[[position]];
    half4 color;
};

vertex
VertexOut particle_vert(constant float2*     positions      [[ buffer(bf_positions_index) ]],
                        constant float*      radii          [[ buffer(bf_radii_index) ]],
                        constant half4*     colors         [[ buffer(bf_colors_index) ]],
                        constant float2*     vertices       [[ buffer(bf_vertices_index) ]],
                        constant float*      lifetimes      [[ buffer(bf_lifetimes_index),function_constant(fc_uses_lifetimes) ]],
                        constant float2&     viewport_size  [[ buffer(bf_viewportSize_index) ]],
                        uint vid                            [[ vertex_id ]],
                        uint iid                            [[ instance_id ]]
                        )
{
    // We shift the position by -1.0 on both x and y axis because of metals viewspace coords
    const float2 fpos = -1.0 + (radii[iid] * vertices[vid] + positions[iid]) / (viewport_size / 2.0);

    VertexOut vOut;
    vOut.position = float4(fpos, 0, 1);
    vOut.color = colors[iid];

    // Fade out based on lifetime
//    vOut.color.a = lifetimes[iid];

    return vOut;
}

struct VertexOutPoint
{
    float4 position[[position]];
    half4 color;
    float pointSize [[point_size]];
};

vertex
VertexOutPoint point_vert(constant float2*     positions      [[ buffer(bf_positions_index) ]],
                          constant half4*      colors         [[ buffer(bf_colors_index) ]],
                          constant float*      radii          [[ buffer(bf_radii_index) ]],
                          constant float*      lifetimes      [[ buffer(bf_lifetimes_index)]],
                          constant float2&     viewport_size  [[ buffer(bf_viewportSize_index) ]],
                          const uint vid                      [[ vertex_id ]]
                          )
{
    // We shift the position by -1.0 on both x and y axis because of metals viewspace coords
    const float2 fpos = -1.0 + (positions[vid]) / (viewport_size / 2.0);

    VertexOutPoint vOut;
    vOut.position = float4(fpos, 0, 1);
    vOut.color = colors[vid];

    // We fade the points out
    vOut.pointSize = radii[vid] * (lifetimes[vid] > 1.0 ? 1.0 : lifetimes[vid]);
    return vOut;
}

struct FragmentOut
{
    half4 color0[[color(0)]];
    half4 color1[[color(1)]];
};

fragment
FragmentOut particle_frag(VertexOut vert [[stage_in]])
{
    return { vert.color, vert.color };
}

fragment
FragmentOut point_frag(VertexOutPoint vert [[stage_in]],
                       const float2 pointCoord [[point_coord]]
                       )
{
    if (length(pointCoord - float2(0.5)) > 0.5) {
        discard_fragment();
    }
    return { vert.color, vert.color };
}
