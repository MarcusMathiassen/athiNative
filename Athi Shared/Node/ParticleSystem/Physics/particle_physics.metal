//
//  particle_collisions.metal
//  Athi
//
//  Created by Marcus Mathiassen on 18/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;
#include "../../../ShaderTypes.h"

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

kernel
void collision_detection_and_resolve(constant MotionParam&      motionParam                 [[buffer(MotionParamIndex)]],
                     constant uint&             collidablesCount            [[buffer(CollidablesCountIndex)]],
                     device Collidable*         collidable                  [[buffer(CollidablesIndex)]],
                     uint                       gid                         [[thread_position_in_grid]])
{
    //----------------------------------
    //  Collision Detection and Resolve
    //----------------------------------

    const uint index = gid;                      // the index of this threads particle
    float2 newPos = collidable[index].position;  // position
    float2 newVel = collidable[index].velocity;  // velocity
    const float radi = collidable[index].radius; // radius
    const float mass = collidable[index].mass;   // mass
    
    for (uint otherIndex = 0; otherIndex < collidablesCount; ++otherIndex) {

        if (index == otherIndex) continue;

        const float2 other_pos = collidable[otherIndex].position;
        const float2 other_vel = collidable[otherIndex].velocity;
        const float other_radi = collidable[otherIndex].radius;
        const float other_mass = collidable[otherIndex].mass;

        if (collision_check(newPos, other_pos, radi, other_radi)) {
            newVel = collision_resolve(newPos, newVel, mass, other_pos, other_vel, other_mass);
        }
    }

    // Update the particle
    collidable[index].velocity = newVel;
    collidable[index].position += newVel;
}
