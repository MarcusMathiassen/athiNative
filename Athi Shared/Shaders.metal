
#include <metal_stdlib>
using namespace metal;

struct Vertex {
    float4 position[[position]];
    float4 color;
};

vertex Vertex vertex_main(constant float2 *position    [[buffer(0)]],
                          constant float4 *color       [[buffer(1)]],
                          constant float4x4 *mvp       [[buffer(2)]],
                          uint vid                     [[vertex_id]])
{
    Vertex vert;
    vert.color = color[vid];
    vert.position = *mvp * float4(position[vid], 0, 1);
    return vert;
}

fragment float4 fragment_main(Vertex vert [[stage_in]]) {
    return vert.color;
}
