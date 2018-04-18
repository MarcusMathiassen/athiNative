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


constant float kGravitationalConstant = 6.67408e-6;

float2 separate(float2 ap, float ar, float2 bp, float br)
{
    // distance
    const float collision_depth = (ar + br) - distance(bp, ap);
    
    const float dx = bp.x - ap.x;
    const float dy = bp.y - ap.y;
    
    // contact angle
    const float collision_angle = atan2(dy, dx);
    const float cos_angle = cos(collision_angle);
    const float sin_angle = sin(collision_angle);
    
    // move the balls away from eachother so they dont overlap
    const float2 a_pos_move = { -collision_depth * 0.5f * cos_angle, -collision_depth * 0.5f * sin_angle };
    
    // Update.
    return ap + a_pos_move;
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
        
        return (scal_norm_1_vec + scal_norm_1_after_vec) * 0.99f;
    }
    return v1;
}

float2 gravity_well(float2 v1,
                    float2 p1,
                    float2 p2,
                    float m1,
                    float m2)
{
    const float dx = p2.x - p1.x;
    const float dy = p2.y - p1.y;
    const float d = distance(p2, p1);
    
    const float angle = atan2(dy, dx);
    const float G = kGravitationalConstant;
    const float F = G * m1 * m2 / d * d;
    
    const float nX = F * cos(angle);
    const float nY = F * sin(angle);
    
    return float2(v1.x + nX, v1.y + nY);
}

float2 repel_from_point(float2 v1,
                        float2 p1,
                        float2 p2,
                        float m1,
                        float m2)
{
    const float dx = p2.x - p1.x;
    const float dy = p2.y - p1.y;
    const float d = distance(p2, p1);
    
    const float angle = atan2(dy, dx);
    const float G = kGravitationalConstant;
    const float F = G * m1 * m2 / d * d;
    
    const float nX = -F * cos(angle);
    const float nY = -F * sin(angle);
    
    return float2(v1.x + nX, v1.y + nY);
}

kernel
void particle_update(constant SimParam&    sim_param        [[buffer(SimParamIndex)]],
                     device float2*        position         [[buffer(PositionIndex)]],
                     device float2*        velocity         [[buffer(VelocityIndex)]],
                     constant float*       radius           [[buffer(RadiusIndex)]],
                     constant float*       mass             [[buffer(MassIndex)]],
                     uint                  gid              [[thread_position_in_grid]]
//                     uint                  lid              [[thread_position_in_threadgroup]],
//                     uint                  lsize            [[threads_per_threadgroup]]
                     )
{
    //----------------------------------
    //  Local variables
    //----------------------------------
    
    // Particle
    const int       id      = gid;

    thread float2   n_pos   = position[id];
    thread float2   n_vel   = velocity[id];
    const float     n_radi  = radius[id];
    const float     n_mass  = mass[id];
    
    // Sim params
    const float2    viewport_size   = sim_param.viewport_size;
    const int       particle_count  = sim_param.particle_count;
    
    //----------------------------------
    //  Particle Collision
    //----------------------------------
    if (sim_param.enable_collisions)
    {
        const int i = gid;

        for (int j = 0; j < particle_count; ++j) {

            if (i == j) continue;

            if (collision_check(n_pos, position[j], n_radi, radius[j])) {
                
//                n_pos = separate(n_pos, n_radi, position[j], radius[j]);
                n_vel = collision_resolve(n_pos, n_vel, n_mass, position[j], velocity[j], mass[j]);
            }
        }
    }
    
    //----------------------------------
    //  GravityWell, Pull, etc.
    //----------------------------------
    {
        if (sim_param.gravity_well_force != 0) {
            n_vel = gravity_well(n_vel, n_pos, sim_param.gravity_well_point, n_mass, sim_param.gravity_well_force);
        }
        
//        if (sim_param.should_repel) {
//            n_vel = -1 * gravity_well(n_vel, n_pos, sim_param.gravity_well_point, n_mass, sim_param.gravity_well_force);
//        }
    }
    
    //----------------------------------
    //  Particle Update
    //----------------------------------
    {
        // Gravity
        n_vel += sim_param.gravity_force;
        
        if (sim_param.enable_border_collisions)
        {
            // Border collision
            if (n_pos.x < 0 + n_radi) {
                n_pos.x = 0 + n_radi;
                n_vel.x *= -1;
            }
            if (n_pos.x > viewport_size.x - n_radi) {
                n_pos.x = viewport_size.x - n_radi;
                n_vel.x *= -1;
            }
            if (n_pos.y < 0 + n_radi) {
                n_pos.y = 0 + n_radi;
                n_vel.y *= -1;
            }
            if (n_pos.y > viewport_size.y - n_radi) {
                n_pos.y = viewport_size.y - n_radi;
                n_vel.y *= -1;
            }
        }
        
        // We wait on every thread before updating the particles position and velocity
        threadgroup_barrier(mem_flags::mem_none);

        // Update the particle
        velocity[id] = n_vel;
        position[id] = n_pos + n_vel;
    }
}
