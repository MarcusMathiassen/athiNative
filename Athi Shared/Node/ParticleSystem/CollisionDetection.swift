//
//  CollisionDetection.swift
//  Athi
//
//  Created by Marcus Mathiassen on 12/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

import simd // dot, sin, cos, float2, etc

protocol Collidable
{
    var id: Int { get set }
    var position: float2 { get set }
    var velocity: float2 { get set }
    var radius: Float { get set }
    var mass: Float { get set }
}

class CollisionDetection<T : Collidable>
{
    var collidables: [T] = []
    
    init(_ newCollidables: [T])
    {
        collidables = newCollidables
    }
    
    func runTimeStep(deltaTime: Float) -> [float2]
    {
        // Assume we at least two collidables
//        precondition(collidables.count > 1, "We assume more than one collidable")
        
        // Holds all new positions
        var newPositions = [float2](repeating: float2(0), count: collidables.count)
        
        for i in collidables.indices {
            
            // Grab the collidable
            let c1 = collidables[i]
            
            var newC1Velocity = float2(0)

            for j in collidables.indices {
                
                // Do not check for collisions with C1
                if i == j { continue }
                
                // Grab the other collidable
                let c2 = collidables[j]
                
                var newC2Velocity = float2(0)

                // If they collide..
                if collisionCheck(c1, c2) {
                    
                    // Resolve the collision
                    (newC1Velocity, newC2Velocity) = collisionResolve(c1, c2)
                }
                
                // Update C2 position
                newPositions[j] += c2.position * (c2.velocity + newC2Velocity) * deltaTime
            }
            
            // Update C1 position
            newPositions[i] += c1.position * (c1.velocity + newC1Velocity) * deltaTime
        }
    
        return newPositions
    }
    
    private func collisionCheck(_ a: T, _ b: T) -> Bool
    {
        // Local variables
        let ax = a.position.x
        let ay = a.position.y
        let bx = b.position.x
        let by = b.position.y
        let ar = a.radius
        let br = b.radius
        
        // square collision check
        if ax - ar < bx + br &&
            ax + ar > bx - br &&
            ay - ar < by + br &&
            ay + ar > by - br {
            
            // circle collision check
            let dx = bx - ax
            let dy = by - ay
            
            let sum_radius = ar + br
            let sqr_radius = sum_radius * sum_radius
            
            let distance_sqrd = (dx * dx) + (dy * dy)
            
            return distance_sqrd < sqr_radius
        }
        
        return false
    }
    
    private func collisionResolve(_ a: T, _ b: T) -> (float2, float2)
    {
        // Local variables
        let dx = b.position.x - a.position.x
        let dy = b.position.y - a.position.y
        let vdx = b.velocity.x - a.velocity.x
        let vdy = b.velocity.y - a.velocity.y
        let v1 = a.velocity
        let v2 = b.velocity
        let m1 = a.mass
        let m2 = b.mass
        
        // A negative 'd' means the circles velocities are in opposite directions
        let d = dx * vdx + dy * vdy
        
        // And we don't resolve collisions between circles moving away from eachother
        if d < 1e-11 {
            let norm = normalize(float2(dx, dy))
            let tang = float2(norm.y * -1.0, norm.x)
            let scal_norm_1 = dot(norm, v1)
            let scal_norm_2 = dot(norm, v2)
            let scal_tang_1 = dot(tang, v1)
            let scal_tang_2 = dot(tang, v2)
            
            let scal_norm_1_after = (scal_norm_1 * (m1 - m2) + 2.0 * m2 * scal_norm_2) / (m1 + m2)
            let scal_norm_2_after = (scal_norm_2 * (m2 - m1) + 2.0 * m1 * scal_norm_1) / (m1 + m2)
            let scal_norm_1_after_vec = norm * scal_norm_1_after
            let scal_norm_2_after_vec = norm * scal_norm_2_after
            let scal_norm_1_vec = tang * scal_tang_1
            let scal_norm_2_vec = tang * scal_tang_2
            
            // Update velocities
            return (scal_norm_1_vec + scal_norm_1_after_vec, scal_norm_2_vec + scal_norm_2_after_vec)
        }
        
        return (v1, v2)
    }
    
    
    // Separates two intersecting circles.
    private func separate(_ a: T, _ b: T) -> (float2, float2)
    {
        // Local variables
        let ap = a.position
        let bp = b.position
        let ar = a.radius
        let br = b.radius
        
        let collisionDepth = (ar + br) - distance(bp, ap)
        
        let dx = bp.x - ap.x
        let dy = bp.y - bp.y
        
        // contact angle
        let collisionAngle = atan2(dy, dx)
        let cosAngle = cos(collisionAngle)
        let sinAngle = sin(collisionAngle)
        
        let aMove = float2(-collisionDepth * 0.5 * cosAngle, -collisionDepth * 0.5 * sinAngle)
        let bMove = float2( collisionDepth * 0.5 * cosAngle,  collisionDepth * 0.5 * sinAngle)
        
        // stores the position offsets
        var apNew = float2(0)
        var bpNew = float2(0)
        
        // Make sure they dont moved beyond the border
        // This will become not needed when borders are segments instead of hardcoded.
        if ap.x + aMove.x >= 0.0 + ar && ap.x + aMove.x <= framebufferWidth - ar {
            apNew.x += aMove.x
        }
        if ap.y + aMove.y >= 0.0 + ar && ap.y + aMove.y <= framebufferHeight - ar {
            apNew.y += aMove.y
        }
        if bp.x + bMove.x >= 0.0 + br && bp.x + bMove.x <= framebufferWidth - br {
            bpNew.x += bMove.x
        }
        if bp.y + bMove.y >= 0.0 + br && bp.y + bMove.y <= framebufferHeight - br {
            bpNew.y += bMove.y
        }
        
        return (apNew, bpNew)
    }
}
