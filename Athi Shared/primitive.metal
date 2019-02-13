
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

vertex Vertex basicVert(constant float2*        position        [[buffer(bf_positions_index)]],
                        constant float4*        color           [[buffer(bf_colors_index)]],
                        constant float2*        radii           [[buffer(bf_radii_index)]],
                        constant float2&        viewport_size   [[buffer(bf_viewportSize_index)]],
                        uint                    vid             [[vertex_id]],
                        uint                    iid             [[instance_id]])
{
    const float2 fpos = -1.0 + (radii[iid] * vertices[vid] + position[iid]) / (viewport_size / 2.0);
    
    Vertex vert;
    vert.color = color[iid];
    vert.position = float4(fpos, 0, 1);
    
    return vert;
}

fragment float4 basicFrag(Vertex vert [[stage_in]]) {
    return vert.color;
}
