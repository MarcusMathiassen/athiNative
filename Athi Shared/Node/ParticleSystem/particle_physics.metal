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

float2 separate(float2 ap, float ar, float2 bp, float br)
{
    // distance
    const float distx = pow(bp.x - ap.x, 2);
    const float disty = pow(bp.y - ap.y, 2);
    const float dist = sqrt(distx - disty);
    const float collision_depth = (ar + br) - dist;
    
    const float dx = bp.x - ap.x;
    const float dy = bp.y - ap.y;
    
    // contact angle
    const float collision_angle = atan2(dy, dx);
    const float cos_angle = cos(collision_angle);
    const float sin_angle = sin(collision_angle);
    
    // move the balls away from eachother so they dont overlap
    const float a_move_x = collision_depth * 0.5f * cos_angle;
    const float a_move_y = collision_depth * 0.5f * sin_angle;
    
    // store the new move values
    float2 a_pos_move;
    
    // Make sure they dont moved beyond the border
    if (ap.x + a_move_x >= -1.0f + ar && ap.x + a_move_x <= 1.0f - ar)
        a_pos_move.x += a_move_x;
    if (ap.y + a_move_y >= -1.0f + ar && ap.y + a_move_y <= 1.0f - ar)
        a_pos_move.y += a_move_y;
    
    // Update.
    return ap + a_pos_move;
}

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
void particle_update(constant SimParam&    sim_param        [[buffer(SimParamIndex)]],
                     device float2*        position         [[buffer(PositionIndex)]],
                     device float2*        velocity         [[buffer(VelocityIndex)]],
                     constant float*       radius           [[buffer(RadiusIndex)]],
                     constant float*       mass             [[buffer(MassIndex)]],
                     uint                  gid              [[thread_position_in_grid]],
                     uint                  lid              [[thread_position_in_threadgroup]],
                     uint                  lsize            [[threads_per_threadgroup]]
                     )
{
    //----------------------------------
    //  Local variables
    //----------------------------------
    
    // Particle
    const int       id      = gid;
    
    float2          n_pos   = position[id];
    float2          n_vel   = velocity[id];
    const float     n_radi  = radius[id];
    const float     n_mass  = mass[id];
    
    // Sim params
    const float2    viewport_size   = sim_param.viewport_size;
    const int       particle_count  = sim_param.particle_count;
    
    //----------------------------------
    //  Particle Collision
    //----------------------------------
    {
        const int i = gid;

        for (int j = 0; j < particle_count; ++j) {

            if (i == j) continue;

            if (collision_check(n_pos, position[j], n_radi, radius[j])) {

                //            n_pos = separate(n_pos, n_radi, position[j], radius[j]);
                n_vel = collision_resolve(n_pos, position[j], n_vel, velocity[j], n_mass, mass[j]);
            }
        }
    }
    
    //----------------------------------
    //  GravityWell, Pull, etc.
    //----------------------------------
    
    
    //----------------------------------
    //  Particle Update
    //----------------------------------
    {
        // Gravity
        n_vel += sim_param.gravity_force;
        
        // Border collision
        if (n_pos.x < 0 + n_radi)                  { n_pos.x = 0 + n_radi; n_vel.x = -n_vel.x; }
        if (n_pos.x > viewport_size.x - n_radi)    { n_pos.x = viewport_size.x - n_radi; n_vel.x = -n_vel.x; }
        if (n_pos.y < 0 + n_radi)                  { n_pos.y = 0 + n_radi; n_vel.y = -n_vel.y; }
        if (n_pos.y > viewport_size.y - n_radi)    { n_pos.y = viewport_size.y - n_radi; n_vel.y = -n_vel.y; }

        // Update the particles value
        velocity[id] = n_vel;
        position[id] = n_pos + n_vel;
    }
}
