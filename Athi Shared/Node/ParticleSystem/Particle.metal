//
//  Particle.metal
//  Athi
//
//  Created by Marcus Mathiassen on 04/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

struct ParticleIn
{
    float2  position;
    float4  color;
    float   size;
};

struct ParticleOut
{
    float4 position[[position]];
    float4 color;
};

struct FragmentOut
{
    float4 color0[[color(0)]];
    float4 color1[[color(1)]];
};

vertex ParticleOut particleVert(constant float2 *vertices          [[buffer(0)]],
                                constant ParticleIn* pIn           [[buffer(1)]],
                                constant float2 *viewportSize      [[buffer(2)]],
                                uint vid                           [[vertex_id]],
                                uint iid                           [[instance_id]])
{
    const float2 fpos = (pIn[iid].size * vertices[vid] + pIn[iid].position) / (*viewportSize / 2.0);

    ParticleOut pOut;
    pOut.position = float4(fpos - 1, 0, 1);
    pOut.color = pIn[iid].color;
    
    return pOut;
}

fragment FragmentOut particleFrag(ParticleOut particle [[stage_in]])
{
    return { particle.color, particle.color };
}
