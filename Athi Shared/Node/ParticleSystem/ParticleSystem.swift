//
//  ParticleSystem.swift
//  Athi
//
//  Created by Marcus Mathiassen on 04/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

import Metal
import MetalKit
import simd
import MetalPerformanceShaders

final class ParticleSystem
{
    ///////////////////
    // Simulation
    ///////////////////
    
    struct BufferIndex
    {
        static let PositionIndex = 0
        static let VelocityIndex = 1
        static let RadiusIndex = 2
        static let MassIndex = 3
        static let ColorIndex = 4
        static let VertexIndex = 5
        static let ViewportIndex = 6
        static let ParticleCountIndex = 7
    }
    
    public var particleCount: Int = 0 // Amount of particles
    
    //      Particle data
    var id:         [Int] = []
    var position:   [float2] = []
    var velocity:   [float2] = []
    var radius:     [Float] = []
    var mass:       [Float] = []
    var color:      [float4] = []
    //
    
    // Options
    var enableMultithreading: Bool = true
    var enableBorderCollision: Bool = true
    var collisionEnergyLoss: Float = 0.98
    var gravityForce: Float = -0.981
    var enableGravity: Bool = false
    var enableCollisions: Bool = true
    var useAccelerometerAsGravity: Bool = false
    var useQuadtree: Bool = true
    var hasInitialVelocity: Bool = true
    var useTreeOptimalSize: Bool = true
    
    var samples: Int = 1
    var isPaused: Bool = false
    
    private var tempGravityForce = float2(0)
    private var shouldUpdate: Bool = false
    private var listOfNodesOfIDs: [[Int]] = []
    private var quadtree: Quadtree?
    
    ///////////////////
    // Rendering
    ///////////////////
    
    /**
        Static data uploaded once, and updated when numVerticesPerParticle is changed
     */
    private var vertices: [float2] = []
    private var indices: [UInt16] = []

    // Metal stuff
    // Rendering stuff
    
    var enablePostProcessing: Bool = true
    var postProcessingSamples: Int = 1
    var blurStrength: Float = 2
    var preAllocatedParticles = 100
    private var particlesAllocatedCount: Int
    #if os(macOS)
    private var dynamicBufferResourceOption: MTLResourceOptions = .storageModeShared
    private var staticBufferResourceOption: MTLResourceOptions = .storageModeShared
    #else
    private var dynamicBufferResourceOption: MTLResourceOptions = .cpuCacheModeWriteCombined
    private var staticBufferResourceOption: MTLResourceOptions = .storageModeShared
    #endif
    var particleColor = float4(1)
    var numVerticesPerParticle = 12
    private var quad: Quad
    private var device: MTLDevice
    private var vertexBuffer: MTLBuffer
    private var indexBuffer: MTLBuffer
    private var pipelineState: MTLRenderPipelineState?
    
    var inTexture: MTLTexture
    var outTexture: MTLTexture
    var finalTexture: MTLTexture
    
    private var computeParticleUpdatePipelineState: MTLComputePipelineState?
    private var computeParticleCollisionPipelineState: MTLComputePipelineState?

    
    private var positionBuffer: MTLBuffer
    private var velocityBuffer: MTLBuffer
    private var radiusBuffer: MTLBuffer
    private var massBuffer: MTLBuffer
    private var colorBuffer: MTLBuffer
    
    
    var bufferSemaphore = DispatchSemaphore(value: 0)
    
    init(device: MTLDevice)
    {
        self.device = device
        quad = Quad(device: device)
        
        let library = device.makeDefaultLibrary()!
        let vertexFunc = library.makeFunction(name: "particle_vert")!
        let fragFunc = library.makeFunction(name: "particle_frag")!
        
        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.label = "pipelineDesc"
        pipelineDesc.vertexFunction = vertexFunc
        pipelineDesc.fragmentFunction = fragFunc
        pipelineDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDesc.colorAttachments[1].pixelFormat = .bgra8Unorm
        

        do {
            try pipelineState = device.makeRenderPipelineState(descriptor: pipelineDesc)
        } catch {
            print("ParticleSystem Pipeline: Creating pipeline state failed")
        }
        
        // Load the kernel function from the library
        let computeParticleUpdateFunc = library.makeFunction(name: "particle_update")
        
        // Create a compute pipeline state
        do {
            try computeParticleUpdatePipelineState = device.makeComputePipelineState(function: computeParticleUpdateFunc!)
        } catch {
            print("Pipeline: Creating pipeline state failed")
        }
        
        // Load the kernel function from the library
        let computeParticleCollisionFunc = library.makeFunction(name: "particle_collision")
        
        // Create a compute pipeline state
        do {
            try computeParticleCollisionPipelineState = device.makeComputePipelineState(function: computeParticleCollisionFunc!)
        } catch {
            print("Pipeline: Creating pipeline state failed")
        }
        
        particlesAllocatedCount = preAllocatedParticles
        vertexBuffer = device.makeBuffer(length: MemoryLayout<float2>.stride * numVerticesPerParticle, options: staticBufferResourceOption)!
        indexBuffer = device.makeBuffer(length: MemoryLayout<UInt16>.stride * numVerticesPerParticle * 3, options: staticBufferResourceOption)!

        
        // The shared buffers used to update the GPUs buffers
        positionBuffer = device.makeBuffer( length: MemoryLayout<float2>.stride * preAllocatedParticles,    options: dynamicBufferResourceOption)!
        velocityBuffer = device.makeBuffer( length: MemoryLayout<float2>.stride * preAllocatedParticles,    options: dynamicBufferResourceOption)!
        radiusBuffer = device.makeBuffer(   length: MemoryLayout<Float>.stride * preAllocatedParticles,     options: dynamicBufferResourceOption)!
        massBuffer = device.makeBuffer(     length: MemoryLayout<Float>.stride * preAllocatedParticles,     options: dynamicBufferResourceOption)!
        colorBuffer = device.makeBuffer(    length: MemoryLayout<float4>.stride * preAllocatedParticles,    options: dynamicBufferResourceOption)!
        
        let inTextureDesc = MTLTextureDescriptor()
        inTextureDesc.height = Int(framebufferHeight)
        inTextureDesc.width = Int(framebufferWidth)
        inTextureDesc.sampleCount = 1
        inTextureDesc.textureType = .type2D
        inTextureDesc.pixelFormat = .bgra8Unorm
        inTextureDesc.resourceOptions = .storageModePrivate
        inTextureDesc.usage = .shaderRead
        inTexture = device.makeTexture(descriptor: inTextureDesc)!
        
        let outTextureDesc = MTLTextureDescriptor()
        outTextureDesc.height = Int(framebufferHeight)
        outTextureDesc.width = Int(framebufferWidth)
        outTextureDesc.sampleCount = 1
        outTextureDesc.textureType = .type2D
        outTextureDesc.pixelFormat = .bgra8Unorm
        outTextureDesc.resourceOptions = .storageModePrivate
        outTextureDesc.usage = .shaderWrite
        outTexture = device.makeTexture(descriptor: outTextureDesc)!
        
        finalTexture = device.makeTexture(descriptor: outTextureDesc)!
        
        buildVertices(numVertices: numVerticesPerParticle)
    }
    public func updateParticlesCollisionsGPU(commandBuffer: MTLCommandBuffer)
    {
        if particleCount < 2 { return }
        
        commandBuffer.pushDebugGroup("Particle GPU Collision")
        
        // Make the encoder
        let computeEncoder = commandBuffer.makeComputeCommandEncoder()
        
        // Set the pipelinestate
        computeEncoder?.setComputePipelineState(computeParticleCollisionPipelineState!)
        
        // Set the buffers
        computeEncoder?.setBytes(&particleCount,    length: MemoryLayout<Int>.stride, index: BufferIndex.ParticleCountIndex)
        computeEncoder?.setBuffer(positionBuffer,   offset: 0, index: BufferIndex.PositionIndex)
        computeEncoder?.setBuffer(velocityBuffer,   offset: 0, index: BufferIndex.VelocityIndex)
        computeEncoder?.setBuffer(radiusBuffer,     offset: 0, index: BufferIndex.RadiusIndex)
        computeEncoder?.setBuffer(massBuffer,       offset: 0, index: BufferIndex.MassIndex)
        
        // Compute kernel threadgroup size
        let w = (computeParticleUpdatePipelineState?.threadExecutionWidth)!
        
        // A one dimensional thread group Swift to pass Metal a one dimensional array
        let threadGroupCount = MTLSize(width:w, height:1, depth:1)
        let threadGroups = MTLSize(width:(particleCount + threadGroupCount.width - 1) / threadGroupCount.width, height:1, depth:1)
        computeEncoder?.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCount)

        print("Particle GPU Collision threadGroupsCount", threadGroupCount)
        print("Particle GPU Collision threadGroups", threadGroups)
        
        // Finish
        computeEncoder?.endEncoding()
        commandBuffer.popDebugGroup()
    }
    
    public func updateParticlesGPU(commandBuffer: MTLCommandBuffer)
    {
        if particleCount == 0 { return }
        
        commandBuffer.pushDebugGroup("Particle GPU Update")
        
        // Make the encoder
        let computeEncoder = commandBuffer.makeComputeCommandEncoder()
        
        // Set the pipelinestate
        computeEncoder?.setComputePipelineState(computeParticleUpdatePipelineState!)
        
        // Set the buffers
        computeEncoder?.setBuffer(positionBuffer,   offset: 0, index: BufferIndex.PositionIndex)
        computeEncoder?.setBuffer(velocityBuffer,   offset: 0, index: BufferIndex.VelocityIndex)
        computeEncoder?.setBuffer(radiusBuffer,     offset: 0, index: BufferIndex.RadiusIndex)
        computeEncoder?.setBytes(&viewportSize,     length: MemoryLayout<float2>.stride, index: BufferIndex.ViewportIndex)

        // Compute kernel threadgroup size
        let w = (computeParticleUpdatePipelineState?.threadExecutionWidth)!
        
        // A one dimensional thread group Swift to pass Metal a one dimensional array
        let threadGroupCount = MTLSize(width:w, height:1, depth:1)
        let threadGroups = MTLSize(width:(particleCount + threadGroupCount.width - 1) / threadGroupCount.width, height:1, depth:1)
        computeEncoder?.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCount)
        
        print("Particle GPU Update threadGroupsCount", threadGroupCount)
        print("Particle GPU Update threadGroups", threadGroups)
        
        // Finish
        computeEncoder?.endEncoding()
        commandBuffer.popDebugGroup()
    }

    public func draw(
        view: MTKView,
        frameDescriptor: FrameDescriptor,
        commandBuffer: MTLCommandBuffer
        )
    {
        if particleCount == 0 { return }
        
        commandBuffer.pushDebugGroup("ParticleSystem Draw")
        
        var renderPassDesc = MTLRenderPassDescriptor()
        renderPassDesc.colorAttachments[0].clearColor = frameDescriptor.clearColor
        renderPassDesc.colorAttachments[0].texture = inTexture
        renderPassDesc.colorAttachments[0].loadAction = .clear
        renderPassDesc.colorAttachments[0].storeAction = .store
        
        renderPassDesc.colorAttachments[1].clearColor = frameDescriptor.clearColor
        renderPassDesc.colorAttachments[1].texture = finalTexture
        renderPassDesc.colorAttachments[1].loadAction = .clear
        renderPassDesc.colorAttachments[1].storeAction = .store
        
        var renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor:   renderPassDesc)!

        renderEncoder.pushDebugGroup("Draw particles (off-screen)")
        renderEncoder.setRenderPipelineState(pipelineState!)
        renderEncoder.setTriangleFillMode(frameDescriptor.fillMode)
        
        updateGPUBuffers(commandBuffer: commandBuffer)
        
        renderEncoder.setVertexBuffer(vertexBuffer,     offset: 0, index: BufferIndex.VertexIndex)
        renderEncoder.setVertexBytes(&viewportSize,     length: MemoryLayout<float2>.stride, index: BufferIndex.ViewportIndex)
        
        renderEncoder.setVertexBuffer(positionBuffer,   offset: 0, index: BufferIndex.PositionIndex)
        renderEncoder.setVertexBuffer(radiusBuffer,     offset: 0, index: BufferIndex.RadiusIndex)
        renderEncoder.setVertexBuffer(colorBuffer,      offset: 0, index: BufferIndex.ColorIndex)
        

        renderEncoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: indices.count,
            indexType: .uint16,
            indexBuffer: indexBuffer,
            indexBufferOffset: 0,
            instanceCount: particleCount)
        
        renderEncoder.popDebugGroup()
        renderEncoder.endEncoding()
        
        if enablePostProcessing {
            
            renderEncoder.pushDebugGroup("Apply Post Processing")

            
            let blurKernel = MPSImageGaussianBlur(device: device, sigma: blurStrength)
            blurKernel.encode(commandBuffer: commandBuffer, sourceTexture: inTexture, destinationTexture: outTexture)

//            quad.pixelate(commandBuffer: commandBuffer, inputTexture: inTexture, outputTexture: finalTexture, sigma: blurStrength)

            
            quad.mix(commandBuffer: commandBuffer, inputTexture1: inTexture, inputTexture2: outTexture, outTexture: finalTexture, sigma: 5.0)
            
//
            renderEncoder.popDebugGroup()
        }
        
        
        renderPassDesc = view.currentRenderPassDescriptor!
        renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc)!
        
        renderEncoder.pushDebugGroup("Draw particles (on-screen)")
        
        quad.draw(renderEncoder: renderEncoder, texture: finalTexture)
        
        renderEncoder.popDebugGroup()
        renderEncoder.endEncoding()
        
        commandBuffer.popDebugGroup()
        
        
        commandBuffer.addCompletedHandler { (commandBuffer) in
            self.bufferSemaphore.signal()
        }
    }
    
    private func updateGPUBuffers(commandBuffer: MTLCommandBuffer)
    {
        // Reallocate more if needed
        if particleCount > particlesAllocatedCount {
            
            // We have to wait until the buffers no longer in use by the GPU
            bufferSemaphore.wait()


            // Reserve space on the CPU buffers
            position.reserveCapacity(   particlesAllocatedCount * MemoryLayout<float2>.stride)
            velocity.reserveCapacity(   particlesAllocatedCount * MemoryLayout<float2>.stride)
            radius.reserveCapacity(     particlesAllocatedCount * MemoryLayout<Float>.stride)
            mass.reserveCapacity(       particlesAllocatedCount * MemoryLayout<Float>.stride)
            color.reserveCapacity(      particlesAllocatedCount * MemoryLayout<float4>.stride)

            // Copy the GPU buffers over to the CPU
            memcpy(&position,   positionBuffer.contents(),  particlesAllocatedCount * MemoryLayout<float2>.stride)
            memcpy(&velocity,   velocityBuffer.contents(),  particlesAllocatedCount * MemoryLayout<float2>.stride)
            memcpy(&radius,     radiusBuffer.contents(),    particlesAllocatedCount * MemoryLayout<Float>.stride)
            memcpy(&mass,       massBuffer.contents(),      particlesAllocatedCount * MemoryLayout<Float>.stride)
            memcpy(&color,      colorBuffer.contents(),     particlesAllocatedCount * MemoryLayout<float4>.stride)

            
            // Update the size of the GPU buffers
            positionBuffer = device.makeBuffer( length: particleCount * MemoryLayout<float2>.stride,    options: dynamicBufferResourceOption)!
            velocityBuffer = device.makeBuffer( length: particleCount * MemoryLayout<float2>.stride,    options: dynamicBufferResourceOption)!
            radiusBuffer = device.makeBuffer(   length: particleCount * MemoryLayout<Float>.stride,     options: dynamicBufferResourceOption)!
            massBuffer = device.makeBuffer(     length: particleCount * MemoryLayout<Float>.stride,     options: dynamicBufferResourceOption)!
            colorBuffer = device.makeBuffer(    length: particleCount * MemoryLayout<float4>.stride,    options: dynamicBufferResourceOption)!
            
            // Copy the CPU buffers back to the GPU
            positionBuffer.contents().copyMemory(   from: &position,    byteCount: particleCount * MemoryLayout<float2>.stride)
            velocityBuffer.contents().copyMemory(   from: &velocity,    byteCount: particleCount * MemoryLayout<float2>.stride)
            radiusBuffer.contents().copyMemory(     from: &radius,      byteCount: particleCount * MemoryLayout<Float>.stride)
            massBuffer.contents().copyMemory(       from: &mass,        byteCount: particleCount * MemoryLayout<Float>.stride)
            colorBuffer.contents().copyMemory(      from: &color,       byteCount: particleCount * MemoryLayout<float4>.stride)
            
            // Update the allocated particle count
            particlesAllocatedCount = particleCount
            
        }
    }

    public func update()
    {
        if isPaused { return }
        
        if shouldUpdate {
            buildVertices(numVertices: numVerticesPerParticle)
            shouldUpdate = false
        }
        
        if enableCollisions {
            for _ in 0 ..< samples
            {
                if enableMultithreading
                {
                    if useQuadtree
                    {
                        // Clear the nodes
                        listOfNodesOfIDs.removeAll()

                        var min: float2
                        var max: float2
                        if useTreeOptimalSize {
                            let (mi, ma) = getMinAndMaxPosition()
                            min = mi
                            max = ma
                            quadtree = Quadtree(min: min, max: max)
//                            quadtreeV2 = QuadtreeV2(bounds: Rect(min: min, max: max), maxCapacity: 5, maxDepth: 3)

                        } else {
//                            quadtreeV2 = QuadtreeV2(bounds: Rect(min: float2(0, 0), max: float2(framebufferWidth, framebufferHeight)), maxCapacity: 50, maxDepth: 5)
                            quadtree = Quadtree(min: float2(0, 0), max: float2(framebufferWidth, framebufferHeight))
                        }
//
//                        quadtreeV2?.setData(positionData: position, radiiData: radius)
//                        quadtreeV2?.insertRange(0 ... particleCount)
//                        quadtreeV2?.getNodesOfIndices(containerOfNodes: &listOfNodesOfIDs)
//
                        quadtree?.setInputData(positions: position, radii: radius)
                        quadtree?.inputRange(range: 0 ... particleCount)

                        quadtree?.getNodesOfIndices(containerOfNodes: &listOfNodesOfIDs)

//                        DispatchQueue.concurrentPerform(iterations: 8) { i in
//                                                let (begin, end) = getBeginAndEnd(i: i, containerSize: listOfNodesOfIDs.count, segments: 8)
//                                                collisionQuadtree(containerOfNodes: listOfNodesOfIDs, begin: begin, end: end)
//                                            }
                        collisionQuadtree(containerOfNodes: listOfNodesOfIDs, begin: 0, end: listOfNodesOfIDs.count)

                    } else { collisionLogNxN(total: particleCount, begin: 0, end: particleCount) }
                    
                } else {
                    if useQuadtree {
                        // Clear the nodes
                        listOfNodesOfIDs.removeAll()

                        var min: float2
                        var max: float2
                        if useTreeOptimalSize {
                            let (mi, ma) = getMinAndMaxPosition()
                            min = mi
                            max = ma
                            quadtree = Quadtree(min: min, max: max)
                        } else {
                            quadtree = Quadtree(min: float2(0, 0), max: float2(framebufferWidth, framebufferHeight))
                        }

                        quadtree?.setInputData(positions: position, radii: radius)
                        quadtree?.inputRange(range: 0 ... particleCount)

                        quadtree?.getNodesOfIndices(containerOfNodes: &listOfNodesOfIDs)

                        collisionQuadtree(containerOfNodes: listOfNodesOfIDs, begin: 0, end: listOfNodesOfIDs.count)

                    } else {
                        collisionLogNxN(total: particleCount, begin: 0, end: particleCount)
                    }
                }
            }
        }

        if enableGravity {
            if useAccelerometerAsGravity {
                tempGravityForce = float2(accelerometer.x, accelerometer.y)
            } else {
                tempGravityForce.y = gravityForce
            }
        } else {
            tempGravityForce *= 0
        }
//
//
//        if enableMultithreading {
////            DispatchQueue.concurrentPerform(iterations: 8) { i in
////                let (begin, end) = getBeginAndEnd(i: i, containerSize: particleCount, segments: 8)
////                print(begin, end)
////                updateParticlesData(begin: begin, end: end)
////            }
//            updateParticlesData(begin: 0, end: particleCount)
//
//        } else {
//            updateParticlesData(begin: 0, end: particleCount)
//        }
    }

    public func setVerticesPerParticle(num: Int)
    {
        numVerticesPerParticle = num
        shouldUpdate = true
    }

    private func buildVertices(numVertices: Int) {
        
        // We cant draw anything with less than 3 vertices so just return
        if numVertices < 3 { return }
        
        // Clear previous values
        vertices.removeAll()
        indices.removeAll()
        
        // Add indices
        for n in 0 ..< numVertices - 2 {
            indices.append(UInt16(0))
            indices.append(UInt16(n + 1))
            indices.append(UInt16(n + 2))
        }

        // Add vertices
        for i in 0 ..< numVertices {
                let cont = Float(i) * Float.pi * 2 / Float(numVertices)
                let x = cos(cont)
                let y = sin(cont)
                vertices.append(float2(x, y))
        }
        
        
        // Update the GPU buffers
        vertexBuffer = device.makeBuffer(bytes: vertices, length: MemoryLayout<float2>.stride * vertices.count, options: staticBufferResourceOption)!
        indexBuffer = device.makeBuffer(bytes: indices, length: MemoryLayout<UInt16>.stride * indices.count, options: staticBufferResourceOption)!
    }
    
    
    //
    private func updateParticlesData(begin: Int, end: Int)
    {
        
        for i in begin ..< end {
            
            var p = self.position[i]
            var v = self.velocity[i]
            let r = self.radius[i]
            
            // Border collision
            if p.x < 0 + r {
                p.x = 0 + r
                v.x = -v.x
            }
            if p.x > framebufferWidth - r {
                p.x = framebufferWidth - r
                v.x = -v.x
            }
            if p.y < 0 + r {
                p.y = 0 + r
                v.y = -v.y
            }
            if p.y > framebufferHeight - r {
                p.y = framebufferHeight - r
                v.y = -v.y
            }
            velocity[i] = v
            position[i] = p
            
            // Update particle positions
            position[i] += velocity[i]
        }
    }
    
    public func eraseParticles()
    {
        position.removeAll()
        velocity.removeAll()
        mass.removeAll()
        radius.removeAll()
        color.removeAll()
        
        particlesAllocatedCount = 0
        
        particleCount = 0
    }
    
    public func colorParticles(IDs: [Int], color: float4)
    {
        for id in IDs {
            self.color[id] = color
        }
    }

    ////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////
    //////////  PHYSICS
    ////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////
    
    private func collisionCheck(_ a: Int, position: float2, radius: Float) -> Bool
    {
        // Local variables
        let ax = self.position[a].x
        let ay = self.position[a].y
        let bx = position.x
        let by = position.y
        let ar = self.radius[a]
        let br = radius
        
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
    
    
    public func goTowardsPoint(_ point: float2, particleIDs: [Int])
    {
        for id in particleIDs {
            velocity[id] = gravityWell(particleID: id, point: point)
        }
    }
    
    public func gravityWell(particleID: Int, point: float2) -> float2
    {
        
        let v1 = velocity[particleID]
        let x1 = position[particleID].x
        let y1 = position[particleID].y
        let x2 = point.x
        let y2 = point.y
        let m1 = mass[particleID]
        let m2 = Float(1e11)
        
        let dx = x2 - x1
        let dy = y2 - y1
        let d = sqrt(dx * dx + dy * dy)
        
        let angle = atan2(dy, dx)
        let G = Float(kGravitationalConstant)
        let F = G * m1 * m2 / d * d
        
        let nX = F * cos(angle)
        let nY = F * sin(angle)
        
        return float2(v1.x + nX, v1.y + nY)
    }
    
    /**
     Returns an array of ids that fit inside the circle
     */
    public func getParticlesInCircle(position: float2, radius: Float) -> [Int] {
        var ids: [Int] = []
        
        // Brute-force
        for b in 0 ..< particleCount {
            
            let bID = id[b]
            
            if collisionCheck(bID, position: position, radius: radius) {
                ids.append(bID)
            }
        }
        
        return ids
    }
    
}
