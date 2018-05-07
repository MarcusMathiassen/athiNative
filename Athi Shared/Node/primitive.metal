
#include <metal_stdlib>
using namespace metal;
#include "../../Resources/Shaders/ShaderTypes.h"

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

vertex Vertex basicVert(constant float2*        position        [[buffer(PositionIndex)]],
                        constant float4*        color           [[buffer(ColorIndex)]],
                        constant float2*        size            [[buffer(SizeIndex)]],
                        constant float2&        viewport_size   [[buffer(ViewportSizeIndex)]],
                        uint                    vid             [[vertex_id]],
                        uint                    iid             [[instance_id]])
{
    const float fposx = -1.0 + (size[iid].x * vertices[vid].x + position[iid].x) / (viewport_size.x / 2.0);
    const float fposy = -1.0 + (size[iid].y * vertices[vid].y + position[iid].y) / (viewport_size.y / 2.0);
    
    const float2 fpos = { fposx, fposy };
    
    Vertex vert;
    vert.color = color[iid];
    vert.position = float4(fpos, 0, 1);
    
    return vert;
}

fragment float4 basicFrag(Vertex vert [[stage_in]]) {
    return vert.color;
}
