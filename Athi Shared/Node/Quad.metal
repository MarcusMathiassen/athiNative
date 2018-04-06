//
//  Quad.metal
//  Athi
//
//  Created by Marcus Mathiassen on 05/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

struct Vertex {
    float4 position[[position]];
    float2 uv;
};

struct BasicVertex {
    float2 position;
    float2 uv;
};

float4 blur13(texture2d<float>  image,
              float2 uv,
              float2 resolution,
              float2 direction)
{
    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear);

    float4 color = float4(0.0);
    float2 off1 = float2(1.411764705882353) * direction;
    float2 off2 = float2(3.2941176470588234) * direction;
    float2 off3 = float2(5.176470588235294) * direction;
    color += image.sample(textureSampler, uv) * 0.1964825501511404;
    color += image.sample(textureSampler, uv + (off1 / resolution)) * 0.2969069646728344;
    color += image.sample(textureSampler, uv - (off1 / resolution)) * 0.2969069646728344;
    color += image.sample(textureSampler, uv + (off2 / resolution)) * 0.09447039785044732;
    color += image.sample(textureSampler, uv - (off2 / resolution)) * 0.09447039785044732;
    color += image.sample(textureSampler, uv + (off3 / resolution)) * 0.010381362401148057;
    color += image.sample(textureSampler, uv - (off3 / resolution)) * 0.010381362401148057;
    return color;
}

vertex Vertex quadVert(    constant BasicVertex *basic_vertex    [[buffer(0)]],
                           uint vid                              [[vertex_id]])
{
    Vertex vert;
    vert.uv = float2(basic_vertex[vid].uv.x, 1 - basic_vertex[vid].uv.y);
    vert.position = float4(basic_vertex[vid].position, 0, 1);
    return vert;
}


fragment float4 quadFrag(Vertex              vert           [[stage_in]],
                         constant float2   *viewportSize    [[buffer(0)]],
                         constant float2   *direction        [[buffer(1)]],
                         texture2d<float>     colorTexture   [[texture(0)]])
{
    return blur13(colorTexture, vert.uv, *viewportSize, *direction);
}
