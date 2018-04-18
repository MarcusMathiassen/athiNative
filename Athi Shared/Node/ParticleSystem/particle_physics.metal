//
//  particle_collisions.metal
//  Athi
//
//  Created by Marcus Mathiassen on 18/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;
#include "particleShaderTypes.h"


bool collision_check(
    float2 ap,
    float2 bp,
    float ar,
    float br
    )
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

float2 collision_resolve(
    float2 ap, 
    float2 bp, 
    float2 av,
    float2 bv,
    float m1,
    float m2
    )
{
    // local variables
    const float dx = bp.x - ap.x;
    const float dy = bp.y - ap.y;
    const float2 a_vel = av;
    const float2 b_vel = bv;
    const float vdx = b_vel.x - a_vel.x;
    const float vdy = b_vel.y - a_vel.y;
    
    // seperate the circles
    // separate_circles(a, b);
    
    const float d = dx * vdx + dy * vdy;
    
    // skip if they're moving away from eachother
    if (d < 0.0) {
        const float2 norm = normalize(float2(dx, dy));
        const float2 tang = float2(norm.y * -1.0f, norm.x);
        
        const float scal_norm_1 = dot(norm, a_vel);
        const float scal_norm_2 = dot(norm, b_vel);
        const float scal_tang_1 = dot(tang, a_vel);
        const float scal_norm_1_after = (scal_norm_1 * (m1 - m2) + 2.0f * m2 * scal_norm_2) / (m1 + m2);
        const float2 scal_norm_1_after_vec = norm * scal_norm_1_after;
        const float2 scal_norm_1_vec = tang * scal_tang_1;
        
        return (scal_norm_1_vec + scal_norm_1_after_vec) * 0.99f;
    }
    return av;
}

kernel
void particle_collision(constant int*      particle_count  [[buffer(ParticleCountIndex)]],
                        device float2*     position        [[buffer(PositionIndex)]],
                        device float2*     velocity        [[buffer(VelocityIndex)]],
                        constant float*    radius          [[buffer(RadiusIndex)]],
                        constant float*    mass            [[buffer(MassIndex)]],
                        uint2              gid             [[thread_position_in_grid]],
                        uint2              lid             [[thread_position_in_threadgroup]],
                        uint2              lsize           [[threads_per_threadgroup]]
                        )
{
    // Total number of particles
    const int total_particles = *particle_count;
    
    const int segments = lsize.x;;
    const int i = lid.x;
    const int parts = total_particles / segments;
    const int leftovers = total_particles % segments;
    const int begin = parts * i;
    int end = parts * (i + 1);
    if (i == segments - 1) { end += leftovers; }
    
    for (int i = begin; i < end; ++i) {

        float2 iv = velocity[i];
        const float2 ip = position[i];
        const float ir = radius[i];
        const float im = mass[i];

        for (int j = 0; j < total_particles; ++j) {

            if (i == j) continue;

            if (collision_check(ip, position[j], ir, radius[j])) {

                velocity[i] += collision_resolve(ip, position[j], iv, velocity[j], im, mass[j]);
            }
        }

        //velocity[i] = iv;
    }
}

kernel
void particle_update(device float2*     position        [[buffer(PositionIndex)]],
                     device float2*     velocity        [[buffer(VelocityIndex)]],
                     constant float*    radius          [[buffer(RadiusIndex)]],
                     constant float2*   viewportSize    [[buffer(ViewportIndex)]],
                     uint2              gid             [[thread_position_in_grid]]
                     )
{
    float2 pos = position[gid.x];
    float2 vel = velocity[gid.x];
    const float r = radius[gid.x];
    
    // Border collision
    if (pos.x < 0 + r)                  { pos.x = 0 + r; vel.x = -vel.x; }
    if (pos.x > viewportSize->x - r)    { pos.x = viewportSize->x - r; vel.x = -vel.x; }
    if (pos.y < 0 + r)                  { pos.y = 0 + r; vel.y = -vel.y; }
    if (pos.y > viewportSize->y - r)    { pos.y = viewportSize->y - r; vel.y = -vel.y; }
    
    // Update the particles value
    velocity[gid.x] = vel;
    position[gid.x] = pos + vel;
}
