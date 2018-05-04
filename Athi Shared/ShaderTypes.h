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
    VertexIndex,
    PositionIndex,
    RadiusIndex,
    ColorIndex,
    
    SizeIndex,
    ViewportSizeIndex,
    MotionParamIndex,
    
    CollidablesIndex,
    CollidablesCountIndex,
    
    ParticlesIndex,
    ParticlesCountIndex,
    
    NeighboursIndex,
    NeighboursIndicesIndex,
};

typedef struct
{
    vector_float2   position;
    vector_float2   velocity;
    float           radius;
    float           mass;
} Particle;

typedef struct
{
    vector_float2   position;
    vector_float2   velocity;
    float           radius;
    float           mass;
} Collidable;

typedef struct
{
    int begin;
    int end;
} Neighbours;

typedef struct
{
    float           deltaTime;       // frame delta time
} MotionParam;

typedef struct
{
    vector_float2 viewportSize;
    vector_float2 attractPoint;
    vector_float2 gravityForce;
    
    vector_float2 mousePos;
    float currentTime;
    
    uint particleCount;
    bool shouldAddParticle;
    vector_float2 newParticlePosition;
    vector_float2 newParticleVelocity;
    float newParticleRadius;
    float newParticleMass;
    vector_float4 newParticleColor;
    float newParticleLifetime;
} SimParam;

#endif /* ShaderTypes_h */

