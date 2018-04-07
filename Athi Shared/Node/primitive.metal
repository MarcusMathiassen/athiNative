
#include <metal_stdlib>
using namespace metal;

struct Vertex {
    float4 position[[position]];
    float4 color;
};

struct basic_vertex {
    float2 position;
    float4 color;
    float2 uv;
};

vertex Vertex basicVert(constant basic_vertex *basicVert [[buffer(0)]],
                        constant float4x4 *mvp [[buffer(1)]],
                        uint vid [[vertex_id]])
{
    Vertex vert;
    vert.color = basicVert[vid].color;
    vert.position = mvp[vid] * float4(basicVert[vid].position, 0, 1);
    return vert;
}

fragment float4 basicFrag(Vertex vert [[stage_in]]) {
    return vert.color;
}
