//
//  ParticleSystem_SoA.swift
//  Athi
//
//  Created by Marcus Mathiassen on 12/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

import simd

final class ParticleSystemSoA
{
    // Amount of particles
    public var particleCount: Int = 0
    
    // Particle
    var id:         [Int] = []
    var position:   [float2] = []
    var velocity:   [float2] = []
    var radius:     [Float] = []
    var mass:       [Float] = []
    var color:      [float4] = []
    
    var containerOfIDs: [[Int]] = []
    
    public func runTimeStep(deltaTime: Float)
    {
        if (particleCount == 0) { return }
        
        containerOfIDs.removeAll()
        
        let (min, max) = getMinAndMaxPosition()
        let quadtree = Quadtree(min: min, max: max)

        quadtree.inputRange(range: 0 ... particleCount)
        quadtree.setInputData(positions: position, radii: radius)
        
        quadtree.getNodesOfIndices(containerOfNodes: &containerOfIDs)
        
        collisionQuadtree(containerOfNodes: containerOfIDs, begin: 0, end: containerOfIDs.count)
        
//        collisionLogNxN(total: particleCount, begin: 0, end: particleCount)
        
        // Update particle
        for i in 0 ..< particleCount {

            let pos = self.position[i]
            let radius = self.radius[i]
            
            // Border collision
            if pos.x < 0 + radius {
                position[i].x = 0 + radius
                velocity[i].x = -velocity[i].x
            }
            if pos.x > framebufferWidth - radius {
                position[i].x = framebufferWidth - radius
                velocity[i].x = -velocity[i].x
            }
            if pos.y < 0 + radius {
                position[i].y = 0 + radius
                velocity[i].y = -velocity[i].y
            }
            if pos.y > framebufferHeight - radius {
                position[i].y = framebufferHeight - radius
                velocity[i].y = -velocity[i].y
            }
            
            // Update particle positions
            position[i] += velocity[i]
        }
    }
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    ////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////
    //////////  PHYSICS
    ////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////


    private func collisionCheck(_ a: Int, _ b: Int) -> Bool
    {
        // Local variables
        let ax = position[a].x
        let ay = position[a].y
        let bx = position[b].x
        let by = position[b].y
        let ar = radius[a]
        let br = radius[b]
        
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
    
    private func collisionResolve(_ a: Int, _ b: Int) -> (float2, float2)
    {
        // Local variables
        let dx = position[b].x - position[a].x
        let dy = position[b].y - position[a].y
        let vdx = velocity[b].x - velocity[a].x
        let vdy = velocity[b].y - velocity[a].y
        let v1 = velocity[a]
        let v2 = velocity[b]
        let m1 = mass[a]
        let m2 = mass[b]
        
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
            return ((scal_norm_1_vec + scal_norm_1_after_vec) * 0.98, (scal_norm_2_vec + scal_norm_2_after_vec) * 0.98)
        }
        
        return (v1, v2)
    }
    
    
    // Separates two intersecting circles.
    private func separate(_ a: Int, _ b: Int) -> (float2, float2)
    {
        // Local variables
        let ap = position[a]
        let bp = position[b]
        let ar = radius[a]
        let br = radius[b]
        
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
        
        return (ap + apNew, bp + bpNew)
    }
    
    private func collisionQuadtree(containerOfNodes: [[Int]], begin: Int, end: Int)
    {
        for k in begin ..< end {
            for i in 0 ..< containerOfNodes[k].count {
                for j in 1 + i ..< containerOfNodes[k].count {
                    
                    let ki = containerOfNodes[k][i]
                    let kj = containerOfNodes[k][j]
                    
                    if collisionCheck(ki, kj) {
                        
                        // Should the circles intersect. Seperate them. If not the next
                        // calculated values will be off.
                        (position[ki], position[kj]) = separate(ki, kj)
                        
                        (velocity[ki], velocity[kj]) = collisionResolve(ki, kj)
                    }
                }
            }
        }
    }
    
    private func collisionLogNxN(total: Int, begin: Int, end: Int)
    {
        for i in begin ..< end {
            for j in 1 + i ..< total {

                if collisionCheck(i, j) {
                    
                    // Should the circles intersect. Seperate them. If not the next
                    // calculated values will be off.
                    (position[i], position[j]) = separate(i, j)
                    
                    (velocity[i], velocity[j]) = collisionResolve(i, j)
                }
            }
        }
    }
    
    
    
    
    
    ////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////
    //////////  UTILITY
    ////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////

    
    
    public func addParticleWith(position: float2, color: float4, radius: Float)
    {
        self.id.append(particleCount)
        self.position.append(position)
        self.velocity.append(randFloat2(-5, 5))
        self.radius.append(radius)
        self.color.append(color)
        //        self.density.append(1)
        self.mass.append(Float.pi * radius * radius)
        
        self.particleCount += 1
    }
    
    public func getParticleDataForGPU() -> [ParticleGPU]
    {
        var result: [ParticleGPU] = []
        for i in 0 ..< particleCount {
            let pd = ParticleGPU.init(position: self.position[i], color: self.color[i], radius: self.radius[i])
            result.append(pd)
        }
        return result
    }
    
    /**
     Returns the minimum and maximum position found of all particles
     */
    public func getMinAndMaxPosition() -> (float2, float2)
    {
        var max = float2(Float((-INT_MAX)), Float(-INT_MAX))
        var min = float2(Float(INT_MAX), Float(INT_MAX))
        
        for i in 0 ..< particleCount {
            
            let pos = position[i]
            
            max.x = (pos.x > max.x) ? pos.x : max.x
            max.y = (pos.y > max.y) ? pos.y : max.y
            min.x = (pos.x < min.x) ? pos.x : min.x
            min.y = (pos.y < min.y) ? pos.y : min.y
        }
        
        return (min, max)
    }
    
    
}
