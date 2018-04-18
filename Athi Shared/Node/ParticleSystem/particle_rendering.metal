//
//  particle_rendering.metal
//  Athi
//
//  Created by Marcus Mathiassen on 18/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;
#include "particleShaderTypes.h"

vertex
ParticleOut particle_vert(constant SimParam& simParam            [[buffer(SimParamIndex)]],
                          constant float2*   position            [[buffer(PositionIndex)]],
                          constant float*    radius              [[buffer(RadiusIndex)]],
                          constant float4*   color               [[buffer(ColorIndex)]],
                          constant float2*   vertices            [[buffer(VertexIndex)]],
                          uint vid                               [[vertex_id]],
                          uint iid                               [[instance_id]]
                         )
{
    // The viewspace position of our vertex.
    // We shift the position by -1.0 on both x and y axis because of metals viewspace coords
    const float2 fpos = -1.0 + (radius[iid] * vertices[vid] + position[iid]) / (simParam.viewport_size / 2.0);
    
    
    ParticleOut pOut;
    pOut.position = float4(fpos, 0, 1);
    pOut.color = color[iid];
    
    return pOut;
}

fragment
FragmentOut particle_frag(ParticleOut particle [[stage_in]])
{
    return { particle.color, particle.color };
}

