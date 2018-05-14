//
//  UtilityFunctions.metal
//  Athi
//
//  Created by Marcus Mathiassen on 07/05/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"
#include "UtilityFunctions.h"

float rand(Seed seed)
{
    int _seed = seed.x + seed.y * 57 + seed.z * 241;
    _seed= (_seed<< 13) ^ _seed;
    return (( 1.0 - ( (_seed * (_seed * _seed * 15731 + 789221) + 1376312589) & 2147483647) / 1073741824.0f) + 1.0f) / 2.0f;
}

float2 rand2(Range<float> range, Seed seed)
{
    const auto inputX = rand(seed);
    const auto inputY = rand({seed.z, seed.y, seed.x});
    
    // Map to range
    const auto slope = 1.0 * (range.max - range.min);
    const auto xr = range.min + slope * (inputX);
    const auto yr = range.min + slope * (inputY);
    
    return {xr, yr};
}

/**
 Return the current point in viewspace
 */
float2 to_viewspace(float2 point, float2 viewport)
{
    auto w = point;
    w.x = -1.0 + 2 * point.x / viewport.x;
    w.y = 1.0 - 2 * point.y / viewport.y;
    w.y *= -1;
    return w;
}

float2 attract_to_point(float2 point, float2 p1, float2 v1, float m1)
{
    return 0.3 * normalize(point - p1) + v1;
}

float2 homingMissile(float2 target,
                     float strength,
                     float2 p1,
                     float2 v1
                     ){
    return 0.3 * normalize(target - p1) + v1;
}


bool collision_check(float2 ap, float2 bp, float ar, float br)
{
    const float ax = ap.x;
    const float ay = ap.y;
    const float bx = bp.x;
    const float by = bp.y;

    // square collision check
    if (ax - ar < bx + br && ax + ar > bx - br && ay - ar < by + br &&
        ay + ar > by - br) {
        // Particle collision check
        const float dx = bx - ax;
        const float dy = by - ay;

        const float sum_radius = ar + br;
        const float sqr_radius = sum_radius * sum_radius;

        const float distance_sqr = (dx * dx) + (dy * dy);

        if (distance_sqr <= sqr_radius) return true;
    }

    return false;
}

float2 collision_resolve(float2 p1, float2 v1, float m1, float2 p2, float2 v2, float m2)
{
    // local variables
    const float2 dp = p2 - p1;
    const float2 dv = v2 - v1;
    const float d = dp.x * dv.x + dp.y * dv.y;

    // We skip any two particles moving away from eachother
    if (d < 0) {
        const float2 norm = normalize(dp);
        const float2 tang = float2(norm.y * -1.0f, norm.x);

        const float scal_norm_1 = dot(norm, v1);
        const float scal_norm_2 = dot(norm, v2);
        const float scal_tang_1 = dot(tang, v1);
        const float scal_norm_1_after = (scal_norm_1 * (m1 - m2) + 2.0f * m2 * scal_norm_2) / (m1 + m2);
        const float2 scal_norm_1_after_vec = norm * scal_norm_1_after;
        const float2 scal_norm_1_vec = tang * scal_tang_1;

        return (scal_norm_1_vec + scal_norm_1_after_vec);
    }
    return v1;
}

// Angle functions
float2 float2_from_angle(float angle)
{
    return normalize(float2(cos(angle), sin(angle)));
}

void update_emitter_indices(device Emitter* emitters,
                            device ushort* emitter_indices,
                            device uint& emitter_count,
                            uint new_emitter_count)
{
    auto counter = emitters[emitter_count].startIndex;
    // Find emitter for this particle
    for (auto emitter_index = emitter_count;
         emitter_index < new_emitter_count; ++emitter_index)
    {
        const auto amount = emitters[emitter_index].startIndex + emitters[emitter_index].particleCount;
        for (auto i = counter; i < amount; ++i)
        {
            emitter_indices[i] = emitter_index;
        }
        counter += amount;
    }
    emitter_count = new_emitter_count;
}

