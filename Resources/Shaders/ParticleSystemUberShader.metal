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
constant bool fc_has_borderBound         [[function_constant(fc_has_borderBound_index)]];
constant bool fc_has_drawToTexture       [[function_constant(fc_has_drawToTexture_index)]];
constant bool fc_has_intercollision      [[function_constant(fc_has_intercollision_index)]];
constant bool fc_has_lifetime            [[function_constant(fc_has_lifetime_index)]];
constant bool fc_has_attractedToMouse    [[function_constant(fc_has_attractedToMouse_index)]];
constant bool fc_has_homing              [[function_constant(fc_has_homing_index)]];

constant bool fc_uses_radii     = fc_has_intercollision || fc_has_borderBound;
constant bool fc_uses_masses    = fc_has_intercollision || fc_has_attractedToMouse;

constant bool fc_uses_texture   = fc_has_drawToTexture;
constant bool fc_uses_colors    = true;

constant bool fc_uses_isAlives  = fc_has_lifetime;
constant bool fc_uses_lifetimes = fc_has_lifetime;
// -------------------------


kernel
void uber_compute(
   device float2*   positions                [[ buffer(bf_positions_index) ]],
   device float2*   velocities               [[ buffer(bf_velocities_index) ]],
   device float*    radii                    [[ buffer(bf_radii_index),       function_constant(fc_uses_radii) ]],
   device float*    masses                   [[ buffer(bf_masses_index),      function_constant(fc_uses_masses) ]],
   device float4*   colors                   [[ buffer(bf_colors_index),      function_constant(fc_uses_colors) ]],
   device bool*     isAlives                 [[ buffer(bf_isAlives_index),    function_constant(fc_uses_isAlives) ]],
   device float*    lifetimes                [[ buffer(bf_lifetimes_index),   function_constant(fc_uses_lifetimes) ]],
   device uint&     gpuParticleCount         [[ buffer(bf_gpuParticleCount_index) ]],

   constant MotionParam&  motionParam        [[ buffer(bf_motionParam_index) ]],
   constant SimParam&     simParam           [[ buffer(bf_simParam_index) ]],

   uint                   gid                [[ thread_position_in_grid ]],

   texture2d<float, access::write>  texture  [[ texture(0), function_constant(fc_uses_texture) ]]
)
{
    // If the particles have been cleared or deleted
    if (simParam.clearParticles) {
        gpuParticleCount = simParam.particleCount;
    }

    //----------------------------------
    //  Local variables
    //----------------------------------
    const uint index = gid;
    float2  pos         = positions[index];
    float2  vel         = velocities[index];
    float4  color       = colors[index];

    float   radius      = radii[index];
    float   mass        = masses[index];

    bool    isAlive     = isAlives[index];
    bool    lifetime    = lifetimes[index];

    if (fc_has_lifetime)
    {
        //----------------------------------
        //  hasLifetime
        //----------------------------------

        // Respawn the particle if dead
        if (!isAlive && !simParam.shouldAddParticle) {

            const float2 randVel = rand2(simParam.newParticleVelocity.x, simParam.newParticleVelocity.y, index, simParam.particleCount/3, 34);

            pos = simParam.newParticlePosition;
            vel = randVel;
            isAlive = true;
            lifetime = simParam.newParticleLifetime;
        }

        // Decrease the lifetime
        lifetime -= motionParam.deltaTime;

        // If the lifetime of this particle has come to an end. Dont update it, dont draw it.
        if (lifetime <= 0) {
            isAlive = false;
        }

        // Fade the particle out until it's dead
        if (fc_uses_colors) {
            color = float4(color.rgb, lifetime);
        }
    }

    if (fc_has_homing)
    {
        vel = homingMissile(simParam.attractPoint, 1.0, pos, vel);
    }

    if (fc_has_attractedToMouse)
    {
        vel = attract_to_point(simParam.attractPoint, pos, vel, mass);
    }


    if (fc_has_intercollision)
    {
        //----------------------------------
        //  interCollision
        //  uses: positions, velocities, radii, masses, simParam,
        //----------------------------------
        for (uint otherIndex = 0; otherIndex < simParam.particleCount; ++otherIndex)
        {
            if (fc_uses_isAlives)
            {
                if (!isAlives[otherIndex]) { continue; }
            }

            if (index == otherIndex) { continue; }

            const float2 other_pos = positions[otherIndex];
            const float other_radi = radii[otherIndex];

            if (collision_check(pos, other_pos, radius, other_radi))
            {
                const float2 other_vel = velocities[otherIndex];
                const float other_mass = masses[otherIndex];

                vel = collision_resolve(pos, vel, mass, other_pos, other_vel, other_mass);
            }
        }
    }

    if (fc_has_borderBound)
    {
        //----------------------------------
        //  borderBound
        //----------------------------------
        if (pos.x < 0 + radius)                        { pos.x = 0 + radius;                          vel.x = -vel.x; }
        if (pos.x > simParam.viewportSize.x - radius)  { pos.x = simParam.viewportSize.x - radius;    vel.x = -vel.x; }
        if (pos.y < 0 + radius)                        { pos.y = 0 + radius;                          vel.y = -vel.y; }
        if (pos.y > simParam.viewportSize.y - radius)  { pos.y = simParam.viewportSize.y - radius;    vel.y = -vel.y; }
    }

    if (fc_has_drawToTexture)
    {
        //----------------------------------
        // uses: positions, colors, simParam, texture
        //----------------------------------
        if (pos.x > 0 && pos.x < simParam.viewportSize.x &&
            pos.y > 0 && pos.y < simParam.viewportSize.y)
        {
            const ushort2 fpos = ushort2(pos.x, simParam.viewportSize.y - pos.y);
            texture.write(colors[gid], fpos);
        }
    }

    {
        //----------------------------------
        //  update
        //  uses: positions, velocities, simParam, gpuParticleCount,
        //----------------------------------

        // The last thread is responsible for adding the new particle
        if (index == gpuParticleCount && simParam.shouldAddParticle)
        {

            // how many particles to add?
            const int amount = simParam.particleCount - gpuParticleCount;
            gpuParticleCount += amount;

            const float2 initalVelocity = simParam.newParticleVelocity;

            // Each new particle gets the same position but different velocities
            for (int i = 1; i < amount; ++i)
            {
                const int newIndex = index+i;

                const float2 randVel = rand2(initalVelocity.x, initalVelocity.y, newIndex, simParam.particleCount/3, 34);

                positions[newIndex] = simParam.newParticlePosition;
                velocities[newIndex] = randVel;

                if (fc_uses_radii)      radii[newIndex] = simParam.newParticleRadius;
                if (fc_uses_masses)     masses[newIndex] = simParam.newParticleMass;
                if (fc_uses_colors)     colors[newIndex] = simParam.newParticleColor;
                if (fc_uses_isAlives)   isAlives[newIndex] = true;
                if (fc_uses_lifetimes)  lifetimes[newIndex] = simParam.newParticleLifetime;
            }
        }

        // Update all used variables
        velocities[index] = vel + simParam.gravityForce;
        positions[index] = pos + vel;

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

struct FragmentOut
{
    vector_float4 color0[[color(0)]];
    vector_float4 color1[[color(1)]];
};

vertex
VertexOut particle_vert(
          constant float2&    viewport_size   [[buffer(bf_viewportSize_index)]],
          constant float2*    positions       [[buffer(bf_positions_index)]],
          constant float*     radii           [[buffer(bf_radii_index)]],
          constant float4*    colors          [[buffer(bf_colors_index)]],
          constant float*     lifetimes       [[buffer(bf_lifetimes_index), function_constant(fc_uses_lifetimes)]],
          constant float2*    vertices        [[buffer(bf_vertices_index)]],
          uint vid                            [[vertex_id]],
          uint iid                            [[instance_id]]
)
{
    // The viewspace position of our vertex.
    // We shift the position by -1.0 on both x and y axis because of metals viewspace coords
    const float2 fpos = -1.0 + (radii[iid] * vertices[vid] + positions[iid]) / (viewport_size / 2.0);

    VertexOut vOut;
    vOut.position = float4(fpos, 0, 1);

    if (fc_has_lifetime) 
        vOut.color = float4(colors[iid].rgb, lifetimes[iid]);
    else 
        vOut.color = colors[iid];

    return vOut;
}

fragment
FragmentOut particle_frag(VertexOut vert [[stage_in]])
{
    return { vert.color, vert.color };
}
