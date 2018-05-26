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
constant bool fc_is_friendly             [[function_constant(9)]];
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

    int particleCount;
    int maxParticleCount;

    int startIndex;

    float attackDamage;
    
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

                  constant GlobalParam&  globalParam [[buffer(bf_globalParam_index)]],

                  const uint index [[ thread_position_in_grid ]]
)
{
    // Get the emitter for this particle
    const auto emitterIndex = emitter_indices[index];
    const auto emitter = emitters[emitterIndex];

    auto  pos = positions[index];
    auto  vel = velocities[index];

    auto  color = colors[index];
    auto  radius = radii[index];

    auto  isAlive = isAlives[index];
    auto  lifetime = lifetimes[index];

    if (lifetime < 0)
    {
        const auto new_vel = emitter.direction * emitter.speed;

        pos = emitter.position;
        vel = new_vel + rand2(-emitter.spread, emitter.spread, index);

        // Update variables if available
        radius = emitter.size;// * 0.8 + emitter.size * rand_f32(0.0, 0.2, globalParam.seed * index);
        color = emitter.color;
        isAlive = true;

        lifetime = emitter.lifetime * (((index + 1.0f - emitter.startIndex) / emitter.particleCount));

    } else {
        lifetime -= globalParam.deltaTime;
        isAlive = true;
    }

    // Update all used variables
    vel += globalParam.gravityForce;

    velocities[index] = vel;
    positions[index] = pos + vel;

    radii[index] = radius;
    colors[index] = color;
    isAlives[index] = isAlive;
    lifetimes[index] = lifetime;
}
