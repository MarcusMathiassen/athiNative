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
    ColorIndex,
    ViewportSizeIndex,
    MotionParamIndex,
    CollidablesIndex,
    CollidablesCountIndex,
};

typedef struct
{
    vector_float2   position;
    vector_float2   velocity;
    float           radius;
    float           mass;
} Collidable;

typedef struct
{
    float           deltaTime;       // frame delta time
} MotionParam;

#endif /* ShaderTypes_h */

