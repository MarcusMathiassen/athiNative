//
//  CollisionDetection.swift
//  Athi
//
//  Created by Marcus Mathiassen on 20/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

import Metal
import MetalKit
import simd

struct MotionParam {
    var deltaTime: Float = 0
}

enum ComputeDeviceOption {
    case CPU
    case GPU
}

enum TreeOption {
    case quadtree
    case noTree
}

struct ComputeParam {
    var isMultithreaded: Bool = true // Application is multithreaded by default.
    var preferredThreadCount: Int = 0// Uses the machines maximum number by default
    var computeDeviceOption: ComputeDeviceOption = .GPU
    var treeOption: TreeOption = .quadtree
}

protocol Collidable {
    var position: float2 { get set }
    var velocity: float2 { get set }
    var radius: Float { get set }
    var mass: Float { get set }
}

final class CollisionDetection <T: Collidable> {
    
    var collidables: [T] = []
    var neighbours: [Neighbours] = []
    var neighbourIndices: [Int32] = []

    var computeParam: ComputeParam! = nil
    var motionParam: MotionParam! = nil
    
    var primitiveRenderer: PrimitiveRenderer
    var quadtree: Quadtree?

    // Metal resources
    var device: MTLDevice
    var collidablesAllocated: Int = 0

    var bufferSemaphore = DispatchSemaphore(value: 1)
    var queue = DispatchQueue(label: "collidablesQueue", attributes: .concurrent)
    
    var computePipelineState: MTLComputePipelineState?
    var computePipelineTreeState: MTLComputePipelineState?
    
    var collidablesBuffer: MTLBuffer
    var neighboursBuffer: MTLBuffer
    var neighboursIndicesBuffer: MTLBuffer
    var neighboursAllocated: Int = 0
    var neighboursIndicesAllocated: Int = 0

    init(device: MTLDevice) {

        self.device = device
        
        primitiveRenderer = PrimitiveRenderer(device: device)

        collidablesBuffer = device.makeBuffer(
            length: MemoryLayout<T>.stride,
            options: .storageModeShared)!
        
        neighboursBuffer = device.makeBuffer(
            length: MemoryLayout<Neighbours>.stride,
            options: .storageModeShared)!
        
        neighboursIndicesBuffer = device.makeBuffer(
            length: MemoryLayout<Int32>.stride,
            options: .storageModeShared)!

        let library = device.makeDefaultLibrary()
        
        let computeFunc = library?.makeFunction(name: "collision_detection_and_resolve")
        do {
            try computePipelineState = device.makeComputePipelineState(function: computeFunc!)
        } catch {
            print("Pipeline: Creating pipeline state failed")
        }
        
        let computeTreeFunc = library?.makeFunction(name: "collision_detection_and_resolve_tree")
        do {
            try computePipelineTreeState = device.makeComputePipelineState(function: computeTreeFunc!)
        } catch {
            print("Pipeline: Creating pipeline state failed")
        }
    }

    /**
     Returns the collidables new position
     */
    public func runTimeStep(commandBuffer: MTLCommandBuffer,
                            collidables: [T],
                            motionParam: MotionParam,
                            computeParam: ComputeParam) -> [T] {

        precondition(collidables.count > 1, "More than one collidable needed")

        // If the collidables.count between calls change, just reset the collidablesAllocated count
        if collidables.count < collidablesAllocated { collidablesAllocated = 0 }
        if neighbours.count < neighboursAllocated { neighboursAllocated = 0 }
        if neighbourIndices.count < neighboursIndicesAllocated { neighboursIndicesAllocated = 0 }

        self.collidables = collidables

        // Update our local versions
        self.computeParam = computeParam
        self.motionParam = motionParam
        
        // Build the neighbours if needed
        switch computeParam.treeOption {
        case .quadtree:  fillNeighbours()
        case .noTree:    break
        }
        
        // Choose which device to compute on
        switch computeParam.computeDeviceOption {
        case .GPU:
            switch computeParam.treeOption {
            case .quadtree: resolveOnGPUTree(commandBuffer: commandBuffer)
            case .noTree: resolveOnGPU(commandBuffer: commandBuffer)
            }

        case .CPU:
            
            if computeParam.isMultithreaded {
                
                switch computeParam.treeOption {
                case .quadtree: break
//                    DispatchQueue.concurrentPerform(iterations: computeParam.preferredThreadCount) { (i) in
//                        let (begin, end) = getBeginAndEnd(i: i, containerSize: collidables.count, segments: computeParam.preferredThreadCount)
//                        resolveRangeWithNeighbours(range: begin ... end)
//                    }

                case .noTree: break
//                    DispatchQueue.concurrentPerform(iterations: computeParam.preferredThreadCount) { (i) in
//                        let (begin, end) = getBeginAndEnd(i: i, containerSize: collidables.count, segments: computeParam.preferredThreadCount)
//                        resolveWithoutTree(range: begin ... end)
//                    }
                }
                
                
                
            } else {
                switch computeParam.treeOption {
                case .quadtree: resolveRangeWithNeighbours(range: 0 ... collidables.count)
                case .noTree:   resolveWithoutTree(range: 0 ... collidables.count)
                }
            }
        }
        
        return self.collidables
    }

    private func resolveOnGPU(commandBuffer: MTLCommandBuffer) {

        commandBuffer.pushDebugGroup("Collidables GPU Collision Detection")

        commandBuffer.addCompletedHandler { (_) in

            memcpy(&self.collidables, self.collidablesBuffer.contents(), self.collidablesAllocated * MemoryLayout<T>.stride)

            self.bufferSemaphore.signal()
        }
    
        let computeEncoder = commandBuffer.makeComputeCommandEncoder()

        computeEncoder?.setComputePipelineState(computePipelineState!)

        // Make sure to update the buffers before computing
        updateGPUBuffers(commandBuffer: commandBuffer)

        computeEncoder?.setBuffer(collidablesBuffer,
                                  offset: 0,
                                  index: BufferIndex.CollidablesIndex.rawValue)

        var collidablesCount = collidables.count
        computeEncoder?.setBytes(&collidablesCount,
                                 length: MemoryLayout<UInt>.stride,
                                 index: BufferIndex.CollidablesCountIndex.rawValue)

        computeEncoder?.setBytes(&motionParam,
                                 length: MemoryLayout<MotionParam>.stride,
                                 index: BufferIndex.MotionParamIndex.rawValue)

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
    
    private func resolveOnGPUTree(commandBuffer: MTLCommandBuffer) {
        
        commandBuffer.pushDebugGroup("Collidables GPU Collision Detection Tree")
        
        commandBuffer.addCompletedHandler { (_) in
            
            memcpy(&self.collidables, self.collidablesBuffer.contents(), self.collidablesAllocated * MemoryLayout<T>.stride)
            
            self.bufferSemaphore.signal()
        }
        
        let computeEncoder = commandBuffer.makeComputeCommandEncoder()
        
        computeEncoder?.setComputePipelineState(computePipelineTreeState!)
        
        // Make sure to update the buffers before computing
        updateGPUBuffers(commandBuffer: commandBuffer)
        
        computeEncoder?.setBuffer(collidablesBuffer,
                                  offset: 0,
                                  index: BufferIndex.CollidablesIndex.rawValue)
        
        computeEncoder?.setBuffer(neighboursBuffer,
                                  offset: 0,
                                  index: BufferIndex.NeighboursIndex.rawValue)
        
        computeEncoder?.setBuffer(neighboursIndicesBuffer,
                                  offset: 0,
                                  index: BufferIndex.NeighboursIndicesIndex.rawValue)
        
        computeEncoder?.setBytes(&motionParam,
                                 length: MemoryLayout<MotionParam>.stride,
                                 index: BufferIndex.MotionParamIndex.rawValue)
        
        // Compute kernel threadgroup size
        let threadExecutionWidth = (computePipelineTreeState?.threadExecutionWidth)!
        
        // A one dimensional thread group Swift to pass Metal a one dimensional array
        let threadGroupCount = MTLSize(
            width: threadExecutionWidth,
            height: 1,
            depth: 1)
        
        let recommendedThreadGroupWidth = (collidablesAllocated + threadGroupCount.width - 1) / threadGroupCount.width
        
        let threadGroups = MTLSize(
            width: recommendedThreadGroupWidth,
            height: 1,
            depth: 1)
        
        computeEncoder?.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCount)
        
        // Finish
        computeEncoder?.endEncoding()
        commandBuffer.popDebugGroup()
    }
    
    private func updateGPUBuffers(commandBuffer: MTLCommandBuffer) {

        if computeParam.treeOption != .noTree {
            if neighbours.count > neighboursAllocated {
                neighboursAllocated = neighbours.count
                neighboursBuffer = device.makeBuffer(
                    length: neighbours.count * MemoryLayout<Neighbours>.stride,
                    options: .storageModeShared)!
            }
            neighboursBuffer.contents().copyMemory(
                from: &neighbours,
                byteCount: neighbours.count * MemoryLayout<Neighbours>.stride)
            
            if neighbourIndices.count > neighboursIndicesAllocated {
                neighboursIndicesAllocated = neighbourIndices.count
                neighboursIndicesBuffer = device.makeBuffer(
                    length: neighbourIndices.count * MemoryLayout<Int32>.stride,
                    options: .storageModeShared)!
            }
            neighboursIndicesBuffer.contents().copyMemory(
                from: &neighbourIndices,
                byteCount: neighbourIndices.count * MemoryLayout<Int32>.stride)
        }
        
        // We need exclusive access to the buffer to make sure our copy is safe and correct
        _ = self.bufferSemaphore.wait(timeout: DispatchTime.distantFuture)
        
        // Resize the buffer if needed
        if collidables.count > collidablesAllocated {
            
            // We copy back the contents
            collidables.reserveCapacity(collidablesAllocated)
            memcpy(&collidables, collidablesBuffer.contents(), collidablesAllocated * MemoryLayout<T>.stride)
            
            // Resize the buffer with the new size
            collidablesBuffer = device.makeBuffer(
                length: collidables.count * MemoryLayout<T>.stride,
                options: MTLResourceOptions.storageModeShared)!
            
            collidablesAllocated = collidables.count
        }
        
        // Update the buffer with our collidables
        collidablesBuffer.contents().copyMemory(
            from: &collidables,
            byteCount: collidables.count * MemoryLayout<T>.stride)
        
        
    }
    
    
    private func fillNeighbours() {
        
        // Clear
        neighbours.removeAll()
        neighbourIndices.removeAll()
        
        let (min, max) = getMinAndMaxPosition(collidables: collidables)
        quadtree = Quadtree(min: min, max: max)
        quadtree?.setInputData(collidables)
        quadtree?.inputRange(range: 0 ... collidables.count)
        
        
        var begin = 0
        var end = 0
        for index in collidables.indices {
            
            var tempNeighbours: [Int32] = []
            quadtree?.getNeighbours(containerOfNodes: &tempNeighbours, collidable: collidables[index])
            neighbourIndices.append(contentsOf: tempNeighbours)
            
            begin   = end
            end     = begin + tempNeighbours.count
            
            let n = Neighbours(begin: Int32(begin), end: Int32(end))
            neighbours.append(n)
        }
    }
    
    public func drawDebug(
        color: float4,
        view: MTKView,
        frameDescriptor: FrameDescriptor,
        commandBuffer: MTLCommandBuffer
        ) {
        
        if collidables.count == 0 { return }
        
        // We only show the quadtree nodes if we're in that mode
        if computeParam.treeOption != .noTree {
            // Draw tree nodes
            var bounds: [Rect] = []
            quadtree?.getNodesBounds(container: &bounds)
            for bound in bounds {
                primitiveRenderer.drawHollowRect(min: bound.min, max: bound.max, color: color)
            }
        }
        
        // Draw collision box around collidables
        for collidable in collidables {
            primitiveRenderer.drawHollowRect(position: collidable.position, color: color, size: collidable.radius, borderWidth: 0.5)
        }
        
        primitiveRenderer.draw(
            view: view,
            frameDescriptor: frameDescriptor,
            commandBuffer: commandBuffer
        )
    }
    
    private func resolveRangeWithNeighbours(range: ClosedRange<Int>) {
        
        for index in range.lowerBound ..< range.upperBound {
            
            // Grab the first collidable
            var coll1 = collidables[index]
            
            let begin: Int = Int(neighbours[index].begin)
            let end: Int = Int(neighbours[index].end)
            
            for neighbourIndex in begin ..< end {
                
                let otherIndex = Int(neighbourIndices[neighbourIndex])
 
                // Dont check with self
                if index == otherIndex { continue }
                
                // Grab the second collidable
                let coll2 = collidables[otherIndex]
                
                // If they collide. Update the first collidable with the new velocity.
                // We accumulate it though, so we add it to our grabbed velocity.
                if checkCollision(coll1, coll2) {
                    coll1.velocity = resolveCollision(coll1, coll2)
                }
            }
            // Update our local version of the particles position with the new velocity
            self.collidables[index].velocity = coll1.velocity
            self.collidables[index].position += coll1.velocity
        }
    }
    private func resolveWithTree(_ treeNodes: [[Int]]) {
        
        for node in treeNodes {
            for index in node {
                
                // Grab the first collidable
                var coll1 = collidables[index]
                
                // Check for collisons with all other collidables
                for otherIndex in node {

                    // Dont check with self
                    if index == otherIndex { continue }

                    // Grab the second collidable
                    let coll2 = collidables[otherIndex]

                    // If they collide. Update the first collidable with the new velocity.
                    // We accumulate it though, so we add it to our grabbed velocity.
                    if (checkCollision(coll1, coll2)) {
                        coll1.velocity = resolveCollision(coll1, coll2)
                    }
                }
                // Update our local version of the particles position with the new velocity
                collidables[index].velocity = coll1.velocity
                collidables[index].position += coll1.velocity
            }
        }
    }
    
    private func resolveWithoutTree(range: ClosedRange<Int>) {
        
        // Compute all new positions and velocities
        for index in range.lowerBound ..< range.upperBound {
            
            // Grab the first collidable
            var coll1 = collidables[index]
            
            // Check for collisons with all other collidables
            for otherIndex in range.lowerBound ..< range.upperBound {
                
                // Dont check with self
                if index == otherIndex { continue }
                
                // Grab the second collidable
                let coll2 = collidables[otherIndex]
                
                // If they collide. Update the first collidable with the new velocity.
                // We accumulate it though, so we add it to our grabbed velocity.
                if (checkCollision(coll1, coll2)) {
                    coll1.velocity = resolveCollision(coll1, coll2)
                }
            }
            // Update our local version of the particles position with the new velocity
            collidables[index].velocity = coll1.velocity
            collidables[index].position += coll1.velocity
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
}
