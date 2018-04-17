//
//  Particle.metal
//  Athi
//
//  Created by Marcus Mathiassen on 04/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

#include <metal_stdlib>
#include "particleShaderTypes.h"
using namespace metal;

vertex
ParticleOut particleVert(constant float2*   position            [[buffer(PositionIndex)]],
                         constant float*    radius              [[buffer(RadiusIndex)]],
                         constant float4*   color               [[buffer(ColorIndex)]],
                         constant float2*   vertices            [[buffer(VertexIndex)]],
                         constant float2*   viewportSize        [[buffer(ViewportIndex)]],
                         uint vid                               [[vertex_id]],
                         uint iid                               [[instance_id]]
                         )
{
    const float2 fpos = (radius[iid] * vertices[vid] + position[iid]) / (*viewportSize / 2.0);

    ParticleOut pOut;
    pOut.position = float4(fpos - 1, 0, 1);
    pOut.color = color[iid];
    
    return pOut;
}

fragment
FragmentOut particleFrag(ParticleOut particle [[stage_in]])
{
    return { particle.color, particle.color };
}



kernel
void particle_update(device float2* position        [[buffer(PositionIndex)]],
                     device float2* velocity        [[buffer(VelocityIndex)]],
                     device float*  radius          [[buffer(RadiusIndex)]],
                     device float2* viewportSize    [[buffer(ViewportIndex)]],
                     uint2          gid             [[thread_position_in_grid]]
                    )
{
    float2 pos  = position[gid.x];
    float2 vel  = velocity[gid.x];
//    float r     = radius[gid.x];
    
//    // Border collision
//    if pos.x < 0 + r { p.position.x = 0 + r; vel.x = -vel.x; }
//    if pos.x > viewportSize.x - r { p.position.x = viewportSize.x - r; vel.x = -vel.x; }
//    if pos.y < 0 + r { p.position.y = 0 + r; vel.y = -vel.y; }
//    if pos.y > viewportSize.y - r { p.position.y = viewportSize.y - r; vel.y = -vel.y; }

    // Update the particles value
    velocity[gid.x] = vel;
    position[gid.x] = pos + vel;
}
