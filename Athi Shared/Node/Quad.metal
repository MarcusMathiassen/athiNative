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

struct Quad {
    float2 position;
    float2 uv;
};

// Our Quad vertices
constexpr constant Quad vertices [] =
{
    {  float2(-1,  1), float2(0, 1) },
    {  float2( 1,  1), float2(1, 1) },
    {  float2( 1, -1), float2(1, 0) },
    
    {  float2(-1,  1), float2(0, 1) },
    {  float2( 1, -1), float2(1, 0) },
    {  float2(-1, -1), float2(0, 0) },
};

float4 blur13(texture2d<float, access::sample>  image,
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

vertex Vertex quadVert(uint vid [[vertex_id]])
{
    Vertex vert;
    vert.uv = float2(vertices[vid].uv.x, 1 - vertices[vid].uv.y);
    vert.position = float4(vertices[vid].position, 0, 1);
    return vert;
}


struct FragOut
{
    float4 color0[[color(0)]];
};


fragment FragOut gaussianBlurFrag(  Vertex                              vert            [[stage_in]],
                                    constant float2*                    resolution      [[buffer(0)]],
                                    constant float2*                    direction       [[buffer(1)]],
                                    texture2d<float, access::sample>    texIn           [[texture(0)]])
{
    return { blur13(texIn, vert.uv, *resolution, *direction)};
}


fragment FragOut quadFrag(  Vertex                              vert           [[stage_in]],
                            texture2d<float, access::sample>    colorTexture   [[texture(0)]])
{
    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear);
    
    // We return the color of the texture
    return { colorTexture.sample(textureSampler, vert.uv) };
}

kernel void pixelate(texture2d<float, access::sample>    texIn           [[texture(0)]],
                     texture2d<float, access::write>     texOut          [[texture(1)]],
                     uint2                               gid             [[thread_position_in_grid]])
{
    const uint weight = 10;
    const uint2 pixellatedGid = uint2((gid.x / weight) * weight, (gid.y / weight) * weight);
    
    const float4 colorAtPixel = texIn.read(pixellatedGid);
    
    texOut.write(colorAtPixel, gid);
}

kernel void mix(texture2d<float, access::read>     tex1          [[texture(0)]],
                texture2d<float, access::read>     tex2          [[texture(1)]],
                texture2d<float, access::write>    dest          [[texture(2)]],
                uint2                              gid           [[thread_position_in_grid]])
{
    float4 c1 = tex1.read(gid);
    float4 c2 = tex2.read(gid);
    float4 rc = c1 + c2;
    
    dest.write(rc, gid);
}
