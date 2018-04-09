//
//  Particle.metal
//  Athi
//
//  Created by Marcus Mathiassen on 04/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

struct Particle
{
    float4 position[[position]];
    float4 color;
};

struct FragColor
{
    float4 color0[[color(0)]];
};

vertex Particle particleVert(
                             constant float2 *position    [[buffer(0)]],
                             constant float4 *color       [[buffer(1)]],
                             constant float4x4 *mvp       [[buffer(2)]],
                             uint vid                     [[vertex_id]],
                             uint iid                     [[instance_id]])
{
    
    Particle particle;
    particle.position = mvp[iid] * float4(position[vid], 0, 1);
    particle.color = color[iid];

    return particle;
}

fragment FragColor particleFrag(
                             Particle particle [[stage_in]])
{
    FragColor frag_color;
    frag_color.color0 = particle.color;
    
    return frag_color;
}
