//
//  CollisionDetection.swift
//  Athi
//
//  Created by Marcus Mathiassen on 20/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

import Metal.MTLDevice

struct MotionParam {
    var deltaTime: Float = 0
}

enum ComputeDeviceOption {
    case CPU
    case GPU
}

enum TreeOption {
    case Quadtree
    case None
}

struct ComputeParam {
    var isMultithreaded: Bool = true // Application is multithreaded by default.
    var preferredThreadCount: Int = 0// Uses the machines maximum number by default
    var computeDeviceOption: ComputeDeviceOption = .GPU
    var treeOption: TreeOption = .Quadtree
}

protocol Collidable {
    var position: float2 { get set }
    var velocity: float2 { get set }
    var radius: Float { get set }
    var mass: Float { get set }
}

final class CollisionDetection <T: Collidable> {

    var collidables: [T] = []
    var newPositions: [float2] = []

    var computeParam: ComputeParam! = nil
    var motionParam: MotionParam! = nil

    /**
        @Lightweight
     */
    init(device: MTLDevice) {
        
    }
    
    /**
     Returns the collidables new position
     */
    public func runTimeStep(
        collidables: [T],
        motionParam: MotionParam,
        computeParam: ComputeParam) -> [T] {

        precondition(collidables.count > 1, "More than one collidable needed")
        
        self.collidables = collidables
        self.newPositions = [float2](repeating: float2(0), count: collidables.count)

        // Update our local versions
        self.computeParam = computeParam
        self.motionParam = motionParam

        // Choose which device to compute on
        switch computeParam.computeDeviceOption {
        case .CPU: resolveOnCPU()
        case .GPU: resolveOnGPU()
        }
        
        return collidables
    }

    private func resolveOnCPU() {
        
        if computeParam.isMultithreaded {
            processRangeCPU(0 ... collidables.count) // @Temporary
        } else {
            processRangeCPU(0 ... collidables.count)
        }
    }

    private func resolveOnGPU() {
        
    }

    private func resolveWithTree(treeNodes: [[Int]], range: ClosedRange<Int>) {
        
        for nodeIndex in range.lowerBound ..< range.upperBound {

            for index in 0 ..< treeNodes[nodeIndex].count {
                
                // Grab the first collidable
                let coll1 = collidables[treeNodes[nodeIndex][index]]
                
                // We accumulate positions and velocities and add them to the original at the end.
                // So we grab them now.
                var newVel = float2(0)
                var newPos = float2(0)
                
                for otherIndex in 0 ..< treeNodes[nodeIndex].count {

                    // Dont check with self
                    if index == otherIndex { continue }
                    
                    // Grab the second collidable
                    let coll2 = collidables[treeNodes[nodeIndex][otherIndex]]
                    
                    // If they collide. Update the first collidable with the new velocity.
                    // We accumulate it though, so we add it to our grabbed velocity.
                    if (checkCollision(coll1, coll2)) {
                        newVel += resolveCollision(coll1, coll2)
                    }
                }
                
                // Update our local version of the particles position with the new velocity
                collidables[index].velocity += newVel * motionParam.deltaTime
                collidables[index].position += newPos + newVel
            }
        }
    }
    
    private func resolveWithoutTree(range: ClosedRange<Int>) {
        
        // Compute all new positions and velocities
        for index in range.lowerBound ..< range.upperBound {
            
            // Grab the first collidable
            let coll1 = collidables[index]
            
            // We accumulate positions and velocities and add them to the original at the end.
            // So we grab them now.
            var newVel = float2(0)
            var newPos = float2(0)
            
            // Check for collisons with all other collidables
            for otherIndex in range.lowerBound ..< range.upperBound {
                
                // Dont check with self
                if index == otherIndex { continue }
                
                // Grab the second collidable
                let coll2 = collidables[otherIndex]
                
                // If they collide. Update the first collidable with the new velocity.
                // We accumulate it though, so we add it to our grabbed velocity.
                if (checkCollision(coll1, coll2)) {
                    newVel += resolveCollision(coll1, coll2)
                }
            }
            
            // Update our local version of the particles position with the new velocity
            collidables[index].velocity += newVel * motionParam.deltaTime
            collidables[index].position += newPos + newVel
        }
    }
    
    private func processRangeCPU(_ range: ClosedRange<Int>) {
        
        // Setup trees if needed
        switch computeParam.treeOption {
            
        case .Quadtree:
            
            let (min, max) = getMinAndMaxPosition(collidables: collidables)
            let quadtree = Quadtree<T>(min: min, max: max)
            quadtree.setInputData(collidables)
            quadtree.inputRange(range: 0 ... collidables.count)
            
            var treeNodes: [[Int]] = []
            quadtree.getNodesOfIndices(containerOfNodes: &treeNodes)
            
            resolveWithTree(treeNodes: treeNodes, range: range)

        case .None:
            
            resolveWithoutTree(range: 0 ... collidables.count)
        }
    }

    private func checkCollision(_ a: T, _ b: T) -> Bool {

        // Local variables
        let ap = a.position
        let bp = b.position
        let ar = a.radius
        let br = b.radius

        // square collision check
        if ap.x - ar < bp.x + br &&
            ap.x + ar > bp.x - br &&
            ap.y - ar < bp.y + br &&
            ap.y + ar > bp.y - br {

            // circle collision check
            let dp = bp - ap

            let sum_radius = ar + br
            let sqr_radius = sum_radius * sum_radius

            let distance_sqrd = (dp.x * dp.x) + (dp.y * dp.y)

            return distance_sqrd < sqr_radius
        }

        return false
    }

    private func resolveCollision(_ a: T, _ b: T) -> float2 {

        // Local variables
        let dp = b.position - a.position
        let dv = b.velocity - a.velocity

        let v1 = a.velocity
        let v2 = b.velocity
        let m1 = a.mass
        let m2 = b.mass

        // A negative 'd' means the circles velocities are in opposite directions
        let d = dp.x * dv.x + dp.y * dv.y

        // And we don't resolve collisions between circles moving away from eachother
        if d < 0 {
            let norm = normalize(dp)
            let tang = float2(norm.y * -1.0, norm.x)
            let scal_norm_1 = dot(norm, v1)
            let scal_norm_2 = dot(norm, v2)
            let scal_tang_1 = dot(tang, v1)

            let scal_norm_1_after = (scal_norm_1 * (m1 - m2) + 2.0 * m2 * scal_norm_2) / (m1 + m2)
            let scal_norm_1_after_vec = norm * scal_norm_1_after
            let scal_norm_1_vec = tang * scal_tang_1

            // Return the new velocity
            return (scal_norm_1_vec + scal_norm_1_after_vec) * 0.98
        }

        // Just return the original velocity
        return v1
    }
    
    // Separates two intersecting circles.
    private func separate(_ a: T, _ b: T) -> float2 {
        
        // Local variables
        let ap = a.position
        let bp = b.position
        let ar = a.radius
        let br = b.radius
        
        let collisionDepth = (ar + br) - distance(bp, ap)
        
        let dp = bp - ap
        
        // contact angle
        let collisionAngle = atan2(dp.y, dp.x)
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
        
        return ap + apNew
    }
    
//    private func collisionQuadtree(containerOfNodes: [[Int]], begin: Int, end: Int) {
//
//        for k in begin ..< end {
//            for i in 0 ..< containerOfNodes[k].count {
//                for j in 1 + i ..< containerOfNodes[k].count {
//
//                    let ki = containerOfNodes[k][i]
//                    let kj = containerOfNodes[k][j]
//
//                    if collisionCheck(ki, kj) {
//
//                        // Should the circles intersect. Seperate them. If not the next
//                        // calculated values will be off.
//                        (position[ki], position[kj]) = separate(ki, kj)
//
//                        (velocity[ki], velocity[kj]) = collisionResolve(ki, kj)
//                    }
//                }
//            }
//        }
//    }
}
