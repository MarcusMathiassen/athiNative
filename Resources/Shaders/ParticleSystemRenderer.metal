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


struct VertexOut
{
    float4  position    [[position]];
    half4   color;
    float   pointSize   [[point_size]];
};

vertex
VertexOut particle_vert(constant float2*     positions      [[ buffer(bf_positions_index) ]],
                        constant half4*      colors         [[ buffer(bf_colors_index) ]],
                        constant float*      radii          [[ buffer(bf_radii_index) ]],
                        constant float*      lifetimes      [[ buffer(bf_lifetimes_index)]],
                        constant float2&     viewport_size  [[ buffer(bf_viewportSize_index) ]],
                        const uint vid                      [[ vertex_id ]]
                        )
{
    // We shift the position by -1.0 on both x and y axis because of metals viewspace coords
    const float2 fpos = -1.0 + (positions[vid]) / (viewport_size / 2.0);

    VertexOut vOut;
    vOut.position = float4(fpos, 0, 1);
    vOut.color = colors[vid];

    // We fade the points out
    vOut.pointSize = radii[vid] * (lifetimes[vid] < 1.0 ? lifetimes[vid] : 1.0);

    return vOut;
}

struct FragmentOut
{
    half4 color0[[color(0)]];
    half4 color1[[color(1)]];
};

fragment
FragmentOut particle_frag(VertexOut             vert        [[stage_in]],
                          const float2          pointCoord  [[point_coord]]
                          )
{
    if (length(pointCoord - float2(0.5)) > 0.5) {
        discard_fragment();
    }
    return { vert.color, vert.color };
}
