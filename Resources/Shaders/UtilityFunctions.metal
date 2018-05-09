//
//  UtilityFunctions.metal
//  Athi
//
//  Created by Marcus Mathiassen on 07/05/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

// Generate a random float in the range [0.0f, 1.0f] using x, y, and z (based on the xor128 algorithm)
float rand(int x, int y, int z)
{
    int seed = x + y * 57 + z * 241;
    seed= (seed<< 13) ^ seed;
    return (( 1.0 - ( (seed * (seed * seed * 15731 + 789221) + 1376312589) & 2147483647) / 1073741824.0f) + 1.0f) / 2.0f;
}

int rand_i32(int min, int max, int seed)
{
    const float in = rand(seed*seed+14, min*seed-523, min*seed+34);
    const float slope = 1.0 * (max - min);
    const int32_t res = min + slope * (in);
    return res;
}

float rand_f32(float min, float max, int seed)
{
    const float sss = rand(seed*seed-123, min*seed+34, min*seed-3);

    // Map to range
    const float slope = 1.0 * (max - min);
    const float res = min + slope * (sss);

    return res;
}

float2 rand2(float min, float max, int x, int y, int z)
{
    const float inputX = rand(x,y,z);
    const float inputY = rand(z,x,y);

    // Map to range
    const float slope = 1.0 * (max - min);
    const float xr = min + slope * (inputX);
    const float yr = min + slope * (inputY);

    return float2(xr, yr);
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


// Noise functions
float fade(float t){return t * t * t * (t * (t * 6 - 15) + 10);}
float lerp(float t, float a, float b){return a + t * (b - a);}
float grad(int32_t hash, float x, float y, float z)
{
    const int32_t h = hash & 15;
    const float u = h < 8 ? x : y;
    const float v = h < 4 ? y : h == 12 || h == 14 ? x : z;
    return ((h & 1) == 0 ? u : -u) + ((h & 2) == 0 ? v : -v);
}

float noise(device int32_t *p, float x, float y, float z)
{
    const int32_t X = static_cast<int32_t>(floor(x)) & 255;
    const int32_t Y = static_cast<int32_t>(floor(y)) & 255;
    const int32_t Z = static_cast<int32_t>(floor(z)) & 255;

    x -= floor(x);
    y -= floor(y);
    z -= floor(z);

    const float u = fade(x);
    const float v = fade(y);
    const float w = fade(z);

    const int A = p[X] + Y, AA = p[A] + Z, AB = p[A + 1] + Z;
    const int B = p[X + 1] + Y, BA = p[B] + Z, BB = p[B + 1] + Z;

    return lerp(w, lerp(v, lerp(u, grad(p[AA], x, y, z),
                                grad(p[BA], x - 1, y, z)),
                        lerp(u, grad(p[AB], x, y - 1, z),
                             grad(p[BB], x - 1, y - 1, z))),
                lerp(v, lerp(u, grad(p[AA + 1], x, y, z - 1),
                             grad(p[BA + 1], x - 1, y, z - 1)),
                     lerp(u, grad(p[AB + 1], x, y - 1, z - 1),
                          grad(p[BB + 1], x - 1, y - 1, z - 1))));
}

void reseed(device int32_t *p, int seed)
{
    for (int32_t i = 0; i < 256; ++i)
    {
        p[i] = i;
    }

    for (int i = 256 - 1; i > 1; --i)
    {
        const int j = rand_i32(0, i, p[i]);

        const auto temp = p[i];
        p[i] = p[j];
        p[j] = temp;
    }

    for (size_t i = 0; i < 256; ++i)
    {
        p[256 + i] = p[i];
    }
}
