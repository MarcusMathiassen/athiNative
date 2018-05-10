//
//  ShaderTypes.h
//  Athi Shared
//
//  Created by Marcus Mathiassen on 02/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

//
//  Header containing types and enum constants shared between Metal shaders and Swift/ObjC source
//

#ifndef ShaderTypes_h
#define ShaderTypes_h

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#define NSInteger metal::int32_t
#include <simd/simd.h>
#else
#import <Foundation/Foundation.h>
#import <simd/simd.h>
#endif

typedef NS_ENUM(NSInteger, BufferIndex)
{
    bf_positions_index,
    bf_velocities_index,
    bf_gpuParticleCount_index,

    bf_radii_index,
    bf_masses_index,

    bf_colors_index,

    bf_isAlives_index,
    bf_lifetimes_index,

    bf_vertices_index,
    bf_viewportSize_index,
    bf_motionParam_index,
    bf_simParam_index,

    bf_seed_buffer_index,
    bf_field_nodes_index,
    bf_emitters_index,
    bf_emitter_indices_index,
};

typedef struct
{
    float           deltaTime;       // frame delta time
} MotionParam;

typedef struct
{
    uint particle_count;
    uint max_particle_count;

    vector_float2 viewport_size;
    vector_float2 gravity_force;
    vector_float2 attract_point;
    vector_float2 mouse_pos;

    // Emitters
    bool add_emitter;
    bool remove_emitter;

    uint selected_emitter;

    uint emitter_count;

    float current_time;
    float delta_time;

} GlobalParam;



typedef struct
{
    vector_float2 viewportSize;
    vector_float2 attractPoint;
    vector_float2 gravityForce;
    
    vector_float2 mousePos;
    float currentTime;

    uint emitter_count;
    uint particleCount;

    bool shouldAddParticle;
    vector_float2 newParticlePosition;
    vector_float2 newParticleVelocity;
    float newParticleRadius;
    float newParticleMass;
    vector_float4 newParticleColor;
    float newParticleLifetime;
    bool clearParticles;
    float initialVelocity;

    uint add_particles_count;
    uint selected_emitter_id;
} SimParam;

typedef struct
{
    uint            particle_count;
    uint            max_particle_count;

    // Option variables
    vector_float2   target_pos;
    vector_float2   gravity_force;

    bool            should_add_particle;
    bool            should_clear_particles;

    // Particle Spawn settings
    vector_float2   position;
    vector_float2   direction;
    vector_float4   color;
    float           speed;
    float           maxSpeed;

} EmitterParam;

typedef struct
{
    uint            particle_count;
    uint            add_particles_count;
    uint            max_particle_count;

    // Option variables
    vector_float2   target_pos;
    vector_float2   gravity_force;

    bool            should_add_particle;
    bool            should_clear_particles;

    bool has_lifetime;
    bool has_intercollision;
    bool has_can_add_particles;
    bool has_borderbound;
    bool has_homing;

    // Particle Spawn settings
    vector_float2   position;
    vector_float2   direction;
    vector_float4   color;

    float           spread;
    float           size;
    float           speed;
    float           maxSpeed;
    float           lifetime;

    uint start_index;
    uint end_index;

} _Emitter;

typedef struct
{
    uint min;
    uint max;
} Range;


#endif /* ShaderTypes_h */

