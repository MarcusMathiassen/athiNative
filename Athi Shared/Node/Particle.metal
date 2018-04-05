//
//  Particle.metal
//  Athi
//
//  Created by Marcus Mathiassen on 04/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

struct Vertex {
    float4 position[[position]];
    float4 color;
};

vertex Vertex particleVert(constant float2 *position    [[buffer(0)]],
                          constant float4 *color       [[buffer(1)]],
                          constant float4x4 *mvp       [[buffer(2)]],
                          uint vid                     [[vertex_id]],
                          uint iid                     [[instance_id]])
{
    Vertex vert;
    vert.color = color[iid];
    vert.position = mvp[iid] * float4(position[vid], 0, 1);
    return vert;
}

fragment float4 particleFrag(Vertex vert [[stage_in]]) {
    return vert.color;
}
