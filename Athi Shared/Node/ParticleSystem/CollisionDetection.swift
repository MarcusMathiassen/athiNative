//
//  CollisionDetection.swift
//  Athi
//
//  Created by Marcus Mathiassen on 20/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

import Metal
import MetalKit

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

    
    // Metal resources
    var device: MTLDevice
    var collidablesAllocated: Int = 0
    
    var bufferSemaphore = DispatchSemaphore(value: 0)
    
    var computePipelineState: MTLComputePipelineState?
    var collidablesBuffer: MTLBuffer
    
    /**
        @Lightweight
     */
    init(device: MTLDevice) {
        self.device = device
        
        collidablesBuffer = device.makeBuffer(
            length: MemoryLayout<T>.stride * 1,
            options: .storageModeShared)!
        
    }
    
    /**
     Returns the collidables new position
     */
    public func runTimeStep(
        commandBuffer: MTLCommandBuffer,
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
        case .GPU: resolveOnGPU(commandBuffer: commandBuffer)
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

    private func resolveOnGPU(commandBuffer: MTLCommandBuffer) {
        
        commandBuffer.pushDebugGroup("Collidables GPU Collision Detection")
        
        // Make sure to update the buffers before computing
        updateGPUBuffers(commandBuffer: commandBuffer)
        
        let computeEncoder = commandBuffer.makeComputeCommandEncoder()
        
        computeEncoder?.setComputePipelineState(computePipelineState!)
        
        computeEncoder?.setBuffer(collidablesBuffer,
                                  offset: 0,
                                  index: BufferIndex.CollidablesIndex.rawValue)
        
        // Compute kernel threadgroup size
        let threadExecutionWidth = (computePipelineState?.threadExecutionWidth)!
        
        // A one dimensional thread group Swift to pass Metal a one dimensional array
        let threadGroupCount = MTLSize(
            width: threadExecutionWidth,
            height: 1,
            depth: 1)
        
        let recommendedThreadGroupWidth = (collidables.count + threadGroupCount.width - 1) / threadGroupCount.width
        
        let threadGroups = MTLSize(
            width: recommendedThreadGroupWidth,
            height: 1,
            depth: 1)
        
        computeEncoder?.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCount)
        
        // Finish
        computeEncoder?.endEncoding()
        commandBuffer.popDebugGroup()
    }

    private func resolveWithTree(treeNodes: [[Int]], range: ClosedRange<Int>) {
        
        for nodeIndex in range.lowerBound ..< range.upperBound {

            for index in 0 ..< treeNodes[nodeIndex].count {
                
                // Grab the first collidable
                let coll1 = collidables[treeNodes[nodeIndex][index]]
                
                // We accumulate positions and velocities and add them to the original at the end.
                // So we grab them now.
                var newVel = float2(0)
                let newPos = float2(0)
                
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
            let newPos = float2(0)
            
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
    
    private func updateGPUBuffers(commandBuffer: MTLCommandBuffer) {
        
        commandBuffer.addCompletedHandler { (commandBuffer) in
            self.bufferSemaphore.signal()
        }
        
        // Reallocate more if needed
        if collidables.count > collidablesAllocated {
            
            // We have to wait until the buffers no longer in use by the GPU
            bufferSemaphore.wait()
            
            // Reserve space on the CPU buffers
            collidables.reserveCapacity(collidablesAllocated * MemoryLayout<Collidable>.stride)
            
            // Copy the GPU buffers over to the CPU
            memcpy(&collidables, collidablesBuffer.contents(), collidablesAllocated * MemoryLayout<Collidable>.stride)
            
            // Update the size of the GPU buffers
            collidablesBuffer = device.makeBuffer(
                length: collidables.count * MemoryLayout<T>.stride,
                options: MTLResourceOptions.storageModeShared)!
            
            // Copy the CPU buffers back to the GPU
            collidablesBuffer.contents().copyMemory(
                from: &collidables,
                byteCount: collidables.count * MemoryLayout<T>.stride)

            // Update the allocated particle count
            collidablesAllocated = collidables.count
        }
    }
}
