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
    PositionIndex,
    VelocityIndex,
    RadiusIndex,
    MassIndex,
    ColorIndex,
    VertexIndex,
    SimParamIndex,
    ComparisonIndex,
};

typedef struct
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
} SimParam;

#endif /* ShaderTypes_h */

