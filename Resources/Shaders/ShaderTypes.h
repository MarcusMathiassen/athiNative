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
    
    bf_sizes_index,
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
    bf_globalParam_index,
    bf_emitterParticleCounts_index,
    CollidablesIndex,
    CollidablesCountIndex,
    NeighboursIndex,
    NeighboursIndicesIndex,
    
};

typedef struct
{
    float           deltaTime;       // frame delta time
} MotionParam;

typedef struct
{
    int begin;
    int end;
} Neighbours;

typedef struct
{
    int particleCount;
    
    vector_float2 viewportSize;
    vector_float2 gravityForce;
    vector_float2 attractPoint;
    vector_float2 mousePos;
    
    int emitterCount;
    
    float currentTime;
    float deltaTime;

    int seed;

} GlobalParam;

#endif /* ShaderTypes_h */

