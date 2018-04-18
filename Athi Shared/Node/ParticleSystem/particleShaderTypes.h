//
//  particleShaderTypes.h
//  Athi
//
//  Created by Marcus Mathiassen on 17/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

#ifndef particleShaderTypes_h
#define particleShaderTypes_h

#include <simd/simd.h>
#include "particleShaderTypes.h"

struct Particle
{
    vector_float2 position;
    vector_float2 velocity;
    float  radius;
    float  mass;
    vector_float4 color;
};

struct ParticleOut
{
    vector_float4 position[[position]];
    vector_float4 color;
};

struct FragmentOut
{
    vector_float4 color0[[color(0)]];
    vector_float4 color1[[color(1)]];
};


struct SimParam
{
    int             particle_count;   // number of particles
    vector_float2   gravity_force;    // force of gravity
    vector_float2   viewport_size;    // size of the current viewport
    float           delta_time;       // frame delta time
    
    vector_float2 gravity_well_point;
    float gravity_well_force;
    
    bool enable_collisions;
    bool enable_border_collisions;
    
    bool should_repel;
};

enum BufferIndex
{
    PositionIndex = 0,
    VelocityIndex = 1,
    RadiusIndex = 2,
    MassIndex = 3,
    ColorIndex = 4,
    VertexIndex = 5,
    SimParamIndex = 6,
};

#endif /* particleShaderTypes_h */
