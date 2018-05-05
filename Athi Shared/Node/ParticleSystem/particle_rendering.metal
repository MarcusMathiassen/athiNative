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
                        constant float*     lifetimes       [[buffer(lifetimesIndex)]],
                        uint vid                            [[vertex_id]],
                        uint iid                            [[instance_id]]
                        )
{
    // The viewspace position of our vertex.
    // We shift the position by -1.0 on both x and y axis because of metals viewspace coords
    const float2 fpos = -1.0 + (radius[iid] * vertices[vid] + position[iid]) / (viewport_size / 2.0);
    
    VertexOut vOut;
    vOut.position = float4(fpos, 0, 1);
    
    constexpr bool has_lifetime = false;
    if constexpr (has_lifetime)
        vOut.color = float4(color[iid].rgb, lifetimes[iid]);
    else
        vOut.color = color[iid];
    
    return vOut;
}

fragment
FragmentOut particle_frag(VertexOut vert [[stage_in]])
{
    return { vert.color, vert.color };
}






// Generate a random float in the range [0.0f, 1.0f] using x, y, and z (based on the xor128 algorithm)
float rand(int x, int y, int z)
{
    int seed = x + y * 57 + z * 241;
    seed= (seed<< 13) ^ seed;
    return (( 1.0 - ( (seed * (seed * seed * 15731 + 789221) + 1376312589) & 2147483647) / 1073741824.0f) + 1.0f) / 2.0f;
}

float2 rand2(float min, float max, int x, int y, int z)
{
    const float inputX = rand(x,y,z);
    const float inputY = rand(z,x,y);
    
    // Map to range
    const float slope = 1.0 * (max - min);
    const float xr = min + slope * (inputX);
    const float yr = min + slope * (inputY);
    
    return float2(xr, yr);
}

float2 attract_to_point(float2 point, float2 p1, float2 v1, float m1)
{
    return m1 * normalize(point - p1) + v1;
}

float2 homingMissile(float2 target,
                     float strength,
                     float2 p1,
                     float2 v1
                     ){
    return strength * normalize(target - p1) + v1;
}


//bool collision_check(float2 ap, float2 bp, float ar, float br)
//{
//    const float ax = ap.x;
//    const float ay = ap.y;
//    const float bx = bp.x;
//    const float by = bp.y;
//    
//    // square collision check
//    if (ax - ar < bx + br && ax + ar > bx - br && ay - ar < by + br &&
//        ay + ar > by - br) {
//        // Particle collision check
//        const float dx = bx - ax;
//        const float dy = by - ay;
//        
//        const float sum_radius = ar + br;
//        const float sqr_radius = sum_radius * sum_radius;
//        
//        const float distance_sqr = (dx * dx) + (dy * dy);
//        
//        if (distance_sqr <= sqr_radius) return true;
//    }
//    
//    return false;
//}
//
//float2 collision_resolve(float2 p1, float2 v1, float m1, float2 p2, float2 v2, float m2)
//{
//    // local variables
//    const float2 dp = p2 - p1;
//    const float2 dv = v2 - v1;
//    const float d = dp.x * dv.x + dp.y * dv.y;
//    
//    // We skip any two particles moving away from eachother
//    if (d < 0) {
//        const float2 norm = normalize(dp);
//        const float2 tang = float2(norm.y * -1.0f, norm.x);
//        
//        const float scal_norm_1 = dot(norm, v1);
//        const float scal_norm_2 = dot(norm, v2);
//        const float scal_tang_1 = dot(tang, v1);
//        const float scal_norm_1_after = (scal_norm_1 * (m1 - m2) + 2.0f * m2 * scal_norm_2) / (m1 + m2);
//        const float2 scal_norm_1_after_vec = norm * scal_norm_1_after;
//        const float2 scal_norm_1_vec = tang * scal_tang_1;
//        
//        return (scal_norm_1_vec + scal_norm_1_after_vec) * 0.98;
//    }
//    return v1;
//}

kernel
void big_compute(
                 device float2*                     positions           [[buffer(0)]],
                 device float2*                     velocities          [[buffer(1)]],
                 device float*                      radii               [[buffer(2)]],
                 device float*                      masses              [[buffer(3)]],
                 device float4*                     colors              [[buffer(4)]],
                 texture2d<float, access::write>    texture             [[texture(0)]],

#ifdef HAS_LIFETIME
                 device bool*                       isAlives            [[buffer(5)]],
                 device float*                      lifetimes           [[buffer(6)]],
#endif

                 device uint&                       gpuParticleCount    [[buffer(7)]],
                 constant MotionParam&              motionParam         [[buffer(8)]],
                 constant SimParam&                 simParam            [[buffer(9)]],
                 uint                               gid                 [[thread_position_in_grid]])
{

    // Local variables
    const uint index = gid;

#ifdef HAS_LIFETIME
    {
        //----------------------------------
        //  hasLifetime
        //----------------------------------

        // Respawn the particle if dead
        if (!isAlives[index] && !simParam.shouldAddParticle) {

            positions[index] = simParam.newParticlePosition;
            velocities[index] = rand2(-5, 5, index, simParam.particleCount/3, 34);
            isAlives[index] = true;
            lifetimes[index] = simParam.newParticleLifetime;
        }

        // Local variables
        bool isAlive = isAlives[index];
        float lifetime = lifetimes[index];

        // Decrease the lifetime
        lifetime -= motionParam.deltaTime;

        // If the lifetime of this particle has come to an end. Dont update it, dont draw it.
        if (lifetime <= 0) isAlive = false;

        // Fade the particle out until it's dead
        colors[index] = float4(colors[index].rgb, lifetime);

        // Update
        lifetimes[index] = lifetime;
        isAlives[index] = isAlive;
    }
#endif

#ifdef HAS_IS_HOMING
    {
        //----------------------------------
        //  isHoming
        //----------------------------------

        // Local variables
        const auto pos = positions[index];
        const auto vel = velocities[index];

        velocities[index] = homingMissile(simParam.attractPoint, 1.0, pos, vel);
    }
#endif

#ifdef HAS_ATTRACTED_TO_MOUSE
    {
        //----------------------------------
        //  attractedToMouse
        //----------------------------------

        // Local variables
        const auto pos = positions[index];
        const auto vel = velocities[index];
        const auto mass = masses[index];

        velocities[index] = attract_to_point(simParam.attractPoint, pos, vel, mass);
    }
#endif

#ifdef HAS_INTERCOLLISION
    {
        //----------------------------------
        //  interCollision
        //----------------------------------

        // Local variables
        auto pos = positions[index];
        auto vel = velocities[index];
        const auto radi = radii[index];
        const auto mass = masses[index];

        for (uint otherIndex = 0; otherIndex < simParam.particleCount; ++otherIndex) {

#ifdef HAS_LIFETIME
            if (!isAlives[otherIndex]) continue;
#endif
            if (index == otherIndex) continue;

            const float2 other_pos = positions[otherIndex];
            const float other_radi = radii[otherIndex];

            if (collision_check(pos, other_pos, radi, other_radi)) {

                const float2 other_vel = velocities[otherIndex];
                const float other_mass = masses[otherIndex];

                vel = collision_resolve(pos, vel, mass, other_pos, other_vel, other_mass);
            }
        }
        positions[index] = pos;
        velocities[index] = vel;
    }
#endif

#ifdef HAS_BORDERBOUND
    {
        //----------------------------------
        //  borderBound
        //----------------------------------

        // Local variables
        auto pos = positions[index];
        auto vel = velocities[index];
        const auto radi = radii[index];
        const auto viewportSize = simParam.viewportSize;

        if (pos.x < 0 + radi)               { pos.x = 0 + radi;                 vel.x = -vel.x; }
        if (pos.x > viewportSize.x - radi)  { pos.x = viewportSize.x - radi;    vel.x = -vel.x; }
        if (pos.y < 0 + radi)               { pos.y = 0 + radi;                 vel.y = -vel.y; }
        if (pos.y > viewportSize.y - radi)  { pos.y = viewportSize.y - radi;    vel.y = -vel.y; }

        positions[index] = pos;
        velocities[index] = vel;
    }
#endif



#ifdef HAS_UPDATE
    {
        //----------------------------------
        //  update
        //----------------------------------

        // The last thread is responsible for adding the new particle
        if (index == gpuParticleCount && simParam.shouldAddParticle) {

            // how many particles to add?
            const int amount =  simParam.particleCount - gpuParticleCount;
            gpuParticleCount = simParam.particleCount;

            // Each new particle gets the same position but different velocities
            for (int i = 0; i < amount; ++i) {

                const int newIndex = index+i;

                const float2 randVel = rand2(-5, 5, newIndex, simParam.particleCount/3, 34);

                positions[newIndex] = simParam.newParticlePosition;
                velocities[newIndex] = randVel;
                radii[newIndex] = simParam.newParticleRadius;
                masses[newIndex] = simParam.newParticleMass;

#ifdef HAS_DRAW
                colors[newIndex] = simParam.newParticleColor;
#endif

#ifdef HAS_LIFETIME
                isAlives[newIndex] = true;
                lifetimes[newIndex] = simParam.newParticleLifetime;
#endif
            }
        }

        // Update
        velocities[index] += simParam.gravityForce;
        positions[index] += velocities[index];


        // If the particles have been cleared or deleted
        if (simParam.clearParticles) {
            gpuParticleCount = 0;
        }
    }
#endif


#ifdef HAS_DRAW
    {
        //----------------------------------
        //  draw
        //----------------------------------
        const float2 viewportSize = simParam.viewportSize;
        const float2 ppos = positions[index];
        if (ppos.x > 0 && ppos.x < viewportSize.x &&
            ppos.y > 0 && ppos.y < viewportSize.y) {

            const ushort2 fpos = ushort2(ppos.x, viewportSize.y - ppos.y);
            texture.write(colors[gid], fpos);
        }
    }
#endif
}
