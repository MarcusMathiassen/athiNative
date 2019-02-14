
#include <metal_stdlib>
using namespace metal;
#include "../Resources/Shaders/ShaderTypes.h"

struct Vertex {
    float4 position[[position]];
    float4 color;
};

constexpr constant float2 vertices [] =
{
    float2(-1,  1),
    float2( 1,  1),
    float2( 1, -1),
    float2(-1, -1),
};

vertex Vertex basicVert(constant float2* positions [[buffer(0)]],
                        constant float2* sizes [[buffer(1)]],
                        constant float4* colors [[buffer(2)]],
                        constant float2& viewport_size [[buffer(bf_viewportSize_index)]],
                        uint vid [[vertex_id]],
                        uint iid [[instance_id]])
{
    const float2 fpos = -1.0 + (sizes[iid] * vertices[vid] + positions[iid]) / (viewport_size / 2.0);
    
    Vertex vert;
    vert.position = float4(fpos, 0, 1);
    vert.color = colors[iid];
    
    return vert;
}

fragment float4 basicFrag(Vertex vert [[stage_in]]) {
    return vert.color;
}
