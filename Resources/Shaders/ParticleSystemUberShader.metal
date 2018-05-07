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
#include "UtilityFunctions.h"

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
constant bool fc_uses_colors    = fc_has_drawToTexture;

constant bool fc_uses_isAlives  = fc_has_lifetime;
constant bool fc_uses_lifetimes = fc_has_lifetime;
// -------------------------


kernel
void uber_compute(
   device float2*                     positions           [[buffer(0)]],
   device float2*                     velocities          [[buffer(1)]],

   device float*                      radii               [[buffer(2), function_constant(fc_uses_radii)]],
   device float*                      masses              [[buffer(3), function_constant(fc_uses_masses)]],

   device float4*                     colors              [[buffer(4), function_constant(fc_uses_colors)]],
   texture2d<float, access::write>    texture             [[texture(0), function_constant(fc_uses_texture)]],

   device bool*                       isAlives            [[buffer(5), function_constant(fc_uses_isAlives)]],
   device float*                      lifetimes           [[buffer(6), function_constant(fc_uses_lifetimes)]],

   device uint&                       gpuParticleCount    [[buffer(7)]],
   constant MotionParam&              motionParam         [[buffer(8)]],
   constant SimParam&                 simParam            [[buffer(9)]],
   uint                               gid                 [[thread_position_in_grid]])
{

    // Local variables
    const uint index = gid;

    if (fc_has_lifetime)
    {
        //----------------------------------
        //  hasLifetime
        //----------------------------------

        // Respawn the particle if dead
        if (!isAlives[index] && !simParam.shouldAddParticle) {

            const float2 randVel = rand2(simParam.newParticleVelocity.x, simParam.newParticleVelocity.y, index, simParam.particleCount/3, 34);

            positions[index] = simParam.newParticlePosition;
            velocities[index] = randVel;
            isAlives[index] = true;
            lifetimes[index] = simParam.newParticleLifetime;
        }

        // Local variables
        bool isAlive = isAlives[index];
        float lifetime = lifetimes[index];

        // Decrease the lifetime
        lifetime -= motionParam.deltaTime;

        // If the lifetime of this particle has come to an end. Dont update it, dont draw it.
        if (lifetime <= 0) isAlive = false;

        // Fade the particle out until it's dead
        if (fc_uses_colors) colors[index] = float4(colors[index].rgb, lifetime);

        // Update
        lifetimes[index] = lifetime;
        isAlives[index] = isAlive;
    }

    if (fc_has_homing)
    {
        // Local variables
        const auto pos = positions[index];
        const auto vel = velocities[index];

        velocities[index] = homingMissile(simParam.attractPoint, 1.0, pos, vel);
    }

    if (fc_has_attractedToMouse)
    {
        // Local variables
        const auto pos = positions[index];
        const auto vel = velocities[index];
        const auto mass = masses[index];

        velocities[index] = attract_to_point(simParam.attractPoint, pos, vel, mass);
    }


    if (fc_has_intercollision)
    {
        //----------------------------------
        //  interCollision
        //----------------------------------

        // Local variables
        auto pos = positions[index];
        auto vel = velocities[index];
        const auto radi = radii[index];
        const auto mass = masses[index];

        for (uint otherIndex = 0; otherIndex < simParam.particleCount; ++otherIndex) {

            if (fc_uses_isAlives) {
                if (!isAlives[otherIndex]) continue;
            }

            if (index == otherIndex) continue;

            const float2 other_pos = positions[otherIndex];
            const float other_radi = radii[otherIndex];

            if (collision_check(pos, other_pos, radi, other_radi)) {

                const float2 other_vel = velocities[otherIndex];
                const float other_mass = masses[otherIndex];

                vel = collision_resolve(pos, vel, mass, other_pos, other_vel, other_mass);
            }
        }
        positions[index] = pos;
        velocities[index] = vel;
    }

    if (fc_has_borderBound)
    {
        //----------------------------------
        //  borderBound
        //----------------------------------

        // Local variables
        auto pos = positions[index];
        auto vel = velocities[index];
        const auto radi = radii[index];
        const auto viewportSize = simParam.viewportSize;

        if (pos.x < 0 + radi)               { pos.x = 0 + radi;                 vel.x = -vel.x; }
        if (pos.x > viewportSize.x - radi)  { pos.x = viewportSize.x - radi;    vel.x = -vel.x; }
        if (pos.y < 0 + radi)               { pos.y = 0 + radi;                 vel.y = -vel.y; }
        if (pos.y > viewportSize.y - radi)  { pos.y = viewportSize.y - radi;    vel.y = -vel.y; }

        positions[index] = pos;
        velocities[index] = vel;
    }

    //----------------------------------
    //  update
    //----------------------------------

    // The last thread is responsible for adding the new particle
    if (index == gpuParticleCount && simParam.shouldAddParticle) {

        // how many particles to add?
        const int amount =  simParam.particleCount - gpuParticleCount;
        gpuParticleCount += amount;

        const float2 initalVelocity = simParam.newParticleVelocity;

        // Each new particle gets the same position but different velocities
        for (int i = 0; i < amount; ++i) {

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

    // Update
    velocities[index] += simParam.gravityForce;
    positions[index] += velocities[index];

    // If the particles have been cleared or deleted
    if (simParam.clearParticles) {
        gpuParticleCount = 0;
    }


    if (fc_has_drawToTexture)
    {
        //----------------------------------
        //  draw
        //----------------------------------
        const float2 viewportSize = simParam.viewportSize;
        const float2 ppos = positions[index];
        if (ppos.x > 0 && ppos.x < viewportSize.x &&
            ppos.y > 0 && ppos.y < viewportSize.y) {

            const ushort2 fpos = ushort2(ppos.x, viewportSize.y - ppos.y);
            texture.write(colors[gid], fpos);
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
VertexOut particle_vert(constant float2&    viewport_size   [[buffer(ViewportSizeIndex)]],
                        constant float2*    positions       [[buffer(PositionIndex)]],
                        constant float*     radii           [[buffer(RadiusIndex)]],
                        constant float4*    colors          [[buffer(ColorIndex)]],
                        constant float*     lifetimes       [[buffer(lifetimesIndex)]],
                        constant float2*    vertices        [[buffer(VertexIndex)]],
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
