//
//  particle_rendering.metal
//  Athi
//
//  Created by Marcus Mathiassen on 18/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;
#include "../../ShaderTypes.h"

struct VertexOut
{
    vector_float4 position[[position]];
    vector_float4 color;
};

struct FragmentOut
{
    vector_float4 color0[[color(0)]];
    vector_float4 color1[[color(1)]];
};

vertex
VertexOut particle_vert(constant float2&    viewport_size   [[buffer(ViewportSizeIndex)]],
                        constant float2*    position        [[buffer(PositionIndex)]],
                        constant float*     radius          [[buffer(RadiusIndex)]],
                        constant float4*    color           [[buffer(ColorIndex)]],
                        constant float2*    vertices        [[buffer(VertexIndex)]],
                        uint vid                            [[vertex_id]],
                        uint iid                            [[instance_id]]
                        )
{
    // The viewspace position of our vertex.
    // We shift the position by -1.0 on both x and y axis because of metals viewspace coords
    const float2 fpos = -1.0 + (radius[iid] * vertices[vid] + position[iid]) / (viewport_size / 2.0);
    
    VertexOut vOut;
    vOut.position = float4(fpos, 0, 1);
    vOut.color = color[iid];
    
    return vOut;
}

fragment
FragmentOut particle_frag(VertexOut vert [[stage_in]])
{
    return { vert.color, vert.color };
}

kernel
void particle_update(constant MotionParam&      motionParam               [[buffer(MotionParamIndex)]],
                     constant float2&           viewportSize              [[buffer(ViewportSizeIndex)]],
                     device Particle*           particles                 [[buffer(ParticlesIndex)]],
                     uint                       gid                       [[thread_position_in_grid]])
{
    float2 pos = particles[gid].position;
    float2 vel = particles[gid].velocity;
    const float radi = particles[gid].radius;
    
    // Border collision
    if (pos.x < 0 + radi)               { pos.x = 0 + radi;                 vel.x = -vel.x; }
    if (pos.x > viewportSize.x - radi)  { pos.x = viewportSize.x - radi;    vel.x = -vel.x; }
    if (pos.y < 0 + radi)               { pos.y = 0 + radi;                 vel.y = -vel.y; }
    if (pos.y > viewportSize.y - radi)  { pos.y = viewportSize.y - radi;    vel.y = -vel.y; }
    
    // Update the particle
    particles[gid].velocity = vel;
    particles[gid].position = pos + vel;
}
