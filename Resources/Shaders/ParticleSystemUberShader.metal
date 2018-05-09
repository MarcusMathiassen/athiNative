//
//  ParticleSystemUberShader.metal
//  Athi
//
//  Created by Marcus Mathiassen on 07/05/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

// ---------Name qualifers---------------
//     fc_*:   Function constant
//     fc_uses_*: Function constant telling if a buffer is used/available
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

constant bool fc_uses_radii     = true;
constant bool fc_uses_masses    = fc_has_intercollision || fc_has_attractedToMouse;

constant bool fc_uses_texture   = fc_has_drawToTexture;
constant bool fc_uses_colors    = true;

constant bool fc_uses_isAlives  = fc_has_lifetime;
constant bool fc_uses_lifetimes = fc_has_lifetime;
// -------------------------

kernel
void uber_compute(device float2*   positions                [[ buffer(bf_positions_index) ]],
                  device float2*   velocities               [[ buffer(bf_velocities_index) ]],
                  device uint&     gpuParticleCount         [[ buffer(bf_gpuParticleCount_index) ]],

                  device float*   radii      [[ buffer(bf_radii_index), function_constant(fc_uses_radii) ]],
                  device float*   masses     [[ buffer(bf_masses_index), function_constant(fc_uses_masses) ]],
                  device float4*  colors     [[ buffer(bf_colors_index), function_constant(fc_uses_colors) ]],
                  device bool*    isAlives   [[ buffer(bf_isAlives_index), function_constant(fc_uses_isAlives) ]],
                  device float*   lifetimes  [[ buffer(bf_lifetimes_index), function_constant(fc_uses_lifetimes) ]],

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
    thread const auto is_first_thread = (index == 0) ? true : false;

    {
        //----------------------------------
        //  Runs once each frame
        //----------------------------------

        // The first thread is responsible for adding the new particle
        if (is_first_thread && simParam.shouldAddParticle)
        {
            // how many particles to add?
            const auto initalVelocity = simParam.newParticleVelocity;

            // Each new particle gets the same position but different velocities
            for (uint newIndex = gpuParticleCount; newIndex < simParam.particleCount; ++newIndex)
            {
                const auto randVel = rand2(initalVelocity.x, initalVelocity.y, newIndex, simParam.particleCount / newIndex, 34);

                positions[newIndex] = simParam.newParticlePosition;
                velocities[newIndex] = randVel;

                if (fc_uses_radii)      radii[newIndex] = simParam.newParticleRadius;
                if (fc_uses_masses)     masses[newIndex] = simParam.newParticleMass;
                if (fc_uses_colors)     colors[newIndex] = simParam.newParticleColor;
                if (fc_uses_isAlives)   isAlives[newIndex] = true;
                if (fc_uses_lifetimes)  lifetimes[newIndex] = simParam.newParticleLifetime * rand(newIndex, simParam.particleCount / newIndex, 34);
            }
            gpuParticleCount = simParam.particleCount;
        }
    }

    thread auto  &pos         = positions[index];
    thread auto  &vel         = velocities[index];

    thread auto  &color       = colors[index];
    thread auto  &radius      = radii[index];

    thread auto  &mass        = masses[index];
    thread auto  &isAlive     = isAlives[index];
    thread auto  &lifetime    = lifetimes[index];

    if (fc_has_lifetime)
    {
        //----------------------------------
        //  hasLifetime
        //----------------------------------

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
            pos = simParam.newParticlePosition;
            vel = rand2(simParam.newParticleVelocity.x, simParam.newParticleVelocity.y, index, simParam.particleCount/3, 34);
            isAlive = true;
            lifetime = simParam.newParticleLifetime * rand(index, simParam.particleCount / lifetime, 34);
        }
    }

    if (fc_has_homing)
    {
        vel = homingMissile(simParam.attractPoint, 1.0, pos, vel);
    }

    if (fc_has_attractedToMouse)
    {
        vel = attract_to_point(simParam.mousePos, pos, vel, mass);
    }

    {
        //----------------------------------
        //  Update
        //  uses: positions, velocities, simParam, gpuParticleCount,
        //----------------------------------

        // Update all used variables
        vel += simParam.gravityForce;
        pos += vel;
    }

    if (fc_has_intercollision)
    {
        //----------------------------------
        //  interCollision
        //  uses: positions, velocities, radii, masses, simParam,
        //----------------------------------

        for (uint otherIndex = 0; otherIndex < gpuParticleCount; ++otherIndex)
        {
            if (index == otherIndex) { continue; }

            if (fc_uses_isAlives)
            {
                if (!isAlives[otherIndex]) { continue; }
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

    if (fc_has_borderBound)
    {
        //----------------------------------
        //  borderBound
        //  uses: radius
        //----------------------------------
        if (pos.x <= 0 + radius)                        { pos.x = radius;                              vel.x *= -1; }
        if (pos.x >= simParam.viewportSize.x - radius)  { pos.x = simParam.viewportSize.x - radius;    vel.x *= -1; }
        if (pos.y <= 0 + radius)                        { pos.y = radius;                              vel.y *= -1; }
        if (pos.y >= simParam.viewportSize.y - radius)  { pos.y = simParam.viewportSize.y - radius;    vel.y *= -1; }
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
}


struct VertexOut
{
    vector_float4 position[[position]];
    vector_float4 color;
};

struct FragmentOut
{
    vector_float4 color0[[color(0)]];
    vector_float4 color1[[color(1)]];
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

fragment
FragmentOut particle_frag(VertexOut vert [[stage_in]])
{
    return { vert.color, vert.color };
}
