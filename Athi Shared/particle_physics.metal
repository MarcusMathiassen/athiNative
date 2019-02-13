//
//  particle_collisions.metal
//  Athi
//
//  Created by Marcus Mathiassen on 18/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;
#include "../Resources/Shaders/ShaderTypes.h"
#include "../Resources/Shaders/UtilityFunctions.h" // collision_check, collision_resolve


struct Collidable
{
    float2 position;
    float2 velocity;
    float radius;
    float mass;
};

kernel
void collision_detection_and_resolve(device Collidable*         collidable                  [[buffer(CollidablesIndex)]],
                                     constant uint&             collidablesCount            [[buffer(CollidablesCountIndex)]],
                                     constant float2&           viewportSize                [[buffer(bf_viewportSize_index)]],
                                     constant MotionParam&      motionParam                 [[buffer(bf_motionParam_index)]],
                                     uint                       gid                         [[thread_position_in_grid]]
) {
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
        const float other_radi = collidable[otherIndex].radius;

        if (collision_check(newPos, other_pos, radi, other_radi)) {

            const float2 other_vel = collidable[otherIndex].velocity;
            const float other_mass = collidable[otherIndex].mass;

            newVel = collision_resolve(newPos, newVel, mass, other_pos, other_vel, other_mass);
        }
    }


    // Border collision
    if (newPos.x < 0 + radi) { newPos.x = 0 + radi; newVel.x = -newVel.x; }
    if (newPos.x > viewportSize.x - radi) { newPos.x = viewportSize.x - radi; newVel.x = -newVel.x; }
    if (newPos.y < 0 + radi) { newPos.y = 0 + radi; newVel.y = -newVel.y; }
    if (newPos.y > viewportSize.y - radi) { newPos.y = viewportSize.y - radi; newVel.y = -newVel.y; }

    // Update the particle
    collidable[index].velocity = newVel;
    collidable[index].position += newVel;
}

kernel
void collision_detection_and_resolve_tree(device Collidable*          collidable                  [[buffer(CollidablesIndex)]],
                                          constant Neighbours*        neighbours                  [[buffer(NeighboursIndex)]],
                                          constant int32_t*           neighboursIndices           [[buffer(NeighboursIndicesIndex)]],
                                          constant float2&            viewportSize                [[buffer(bf_viewportSize_index)]],
                                          constant MotionParam&       motionParam                 [[buffer(bf_motionParam_index)]],
                                          uint                        gid                         [[thread_position_in_grid]]
) {
    //----------------------------------
    //  Collision Detection and Resolve
    //----------------------------------

    const int index = gid;                       // the index of this threads particle
    float2 newPos = collidable[index].position;  // position
    float2 newVel = collidable[index].velocity;  // velocity
    const float radi = collidable[index].radius; // radius
    const float mass = collidable[index].mass;   // mass

    const int begin = neighbours[index].begin;
    const int end   = neighbours[index].end;

    for (int neighbour_index = begin; neighbour_index < end; ++neighbour_index) {

        const int otherIndex = neighboursIndices[neighbour_index];

        if (index == otherIndex) continue;

        const float2 other_pos = collidable[otherIndex].position;
        const float other_radi = collidable[otherIndex].radius;

        if (collision_check(newPos, other_pos, radi, other_radi)) {

            const float2 other_vel = collidable[otherIndex].velocity;
            const float other_mass = collidable[otherIndex].mass;

            newVel = collision_resolve(newPos, newVel, mass, other_pos, other_vel, other_mass);
        }
    }
    
    // Border collision
    if (newPos.x < 0 + radi) { newPos.x = 0 + radi; newVel.x = -newVel.x; }
    if (newPos.x > viewportSize.x - radi) { newPos.x = viewportSize.x - radi; newVel.x = -newVel.x; }
    if (newPos.y < 0 + radi) { newPos.y = 0 + radi; newVel.y = -newVel.y; }
    if (newPos.y > viewportSize.y - radi) { newPos.y = viewportSize.y - radi; newVel.y = -newVel.y; }

    // Update the particle
    collidable[index].velocity = newVel;
    collidable[index].position += newVel;
}
