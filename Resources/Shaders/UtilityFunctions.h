//
//  UtilityFunctions.h
//  Athi
//
//  Created by Marcus Mathiassen on 07/05/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

#ifndef UtilityFunctions_h
#define UtilityFunctions_h

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#define NSInteger metal::int32_t
#include <simd/simd.h>
#else
#import <Foundation/Foundation.h>
#import <simd/simd.h>
#endif

float rand(int x, int y, int z);
float2 rand2(float min, float max, int x, int y, int z);

float2 attract_to_point(float2 point, float2 p1, float2 v1, float m1);
float2 homingMissile(float2 target, float strength, float2 p1, float2 v1);

bool collision_check(float2 ap, float2 bp, float ar, float br);
float2 collision_resolve(float2 p1, float2 v1, float m1, float2 p2, float2 v2, float m2);

#endif /* UtilityFunctions_h */
