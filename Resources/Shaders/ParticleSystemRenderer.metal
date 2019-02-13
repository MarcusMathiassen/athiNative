//
//  ParticleSystemRenderer.metal
//  Athi
//
//  Created by Marcus Mathiassen on 15/05/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"

constexpr constant float2 quadVertices[] =
{
    float2(-1,  1),
    float2( 1,  1),
    float2( 1, -1),
    float2(-1, -1),
};

constexpr constant float2 quadUvs[] =
{
    float2( 0,  1),
    float2( 1,  1),
    float2( 1,  0),
    float2( 0,  0),
};

struct VertexOut
{
    float4  position    [[position]];
    float2  uv;
    half4   color;
};

struct FragmentOut
{
    half4 color0 [[color(0)]];
    half4 color1 [[color(1)]];
};

vertex
VertexOut particleVert( constant float2*      positions      [[ buffer(0) ]],
                        constant float*       size          [[ buffer(1) ]],
                        constant half4*       colors         [[ buffer(2) ]],
                        constant float2&      viewportSize   [[ buffer(bf_viewportSize_index) ]],
                        const uint vid                      [[ vertex_id ]],
                        const uint iid                      [[ instance_id ]]
                       )
{
    // We shift the position by -1.0 on both x and y axis because of metals viewspace coords
    const float2 fpos = -1.0 + (size[iid] * quadVertices[vid] + positions[iid]) / (viewportSize / 2.0);

    VertexOut vOut;
    vOut.position = float4(fpos, 0, 1);
    vOut.color = colors[iid];
    vOut.uv = quadUvs[vid];

    return vOut;
}

fragment
FragmentOut particleFrag( VertexOut             vert                [[ stage_in ]],
                          texture2d<half>       particleTexture     [[ texture(0) ]]
                         )
{
    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear);

    // We return the color of the texture
    return {
        particleTexture.sample(textureSampler, vert.uv) * vert.color,
        particleTexture.sample(textureSampler, vert.uv) * vert.color
    };
}
