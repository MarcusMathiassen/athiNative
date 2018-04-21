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

final class ParticleSystem {

    struct Particle: Collidable {

        var position: float2 = float2(0)
        var velocity: float2 = float2(0)
        var radius: Float = 0
        var mass: Float = 0
    }

    private var particles: [Particle] = []

    var collisionDetection: CollisionDetection<Particle>

    public var particleCount: Int = 0 // Amount of particles

    // Options
    var shouldRepel: Bool = false
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
    var positions: [float2] = []
    var radii: [Float] = []
    var colors: [float4] = []

    var enablePostProcessing: Bool = true
    var postProcessingSamples: Int = 1
    var blurStrength: Float = 10
    var preAllocatedParticles = 1
    private var particlesAllocatedCount: Int = 0
    #if os(macOS)
    private var dynamicBufferResourceOption: MTLResourceOptions = .storageModeShared
    private var staticBufferResourceOption: MTLResourceOptions = .storageModeShared
    #else
    private var dynamicBufferResourceOption: MTLResourceOptions = .cpuCacheModeWriteCombined
    private var staticBufferResourceOption: MTLResourceOptions = .storageModeShared
    #endif
    var particleColor = float4(1)
    var numVerticesPerParticle = 36
    private var quad: Quad
    private var device: MTLDevice

    private var vertexBuffer: MTLBuffer
    private var indexBuffer: MTLBuffer

    private var particlesBuffer: MTLBuffer
    
    private var positionBuffer: MTLBuffer
    private var radiusBuffer: MTLBuffer
    private var colorBuffer: MTLBuffer

    private var pipelineState: MTLRenderPipelineState?
    private var computePipelineState: MTLComputePipelineState?

    var inTexture: MTLTexture
    var outTexture: MTLTexture
    var finalTexture: MTLTexture

    var bufferSemaphore = DispatchSemaphore(value: 1)

    init(device: MTLDevice) {
        self.device = device
        quad = Quad(device: device)

        collisionDetection = CollisionDetection<Particle>(device: device)

        let library = device.makeDefaultLibrary()!
        let vertexFunc = library.makeFunction(name: "particle_vert")!
        let fragFunc = library.makeFunction(name: "particle_frag")!

        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.label = "pipelineDesc"
        pipelineDesc.vertexFunction = vertexFunc
        pipelineDesc.fragmentFunction = fragFunc
        pipelineDesc.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        pipelineDesc.colorAttachments[1].pixelFormat = .bgra8Unorm_srgb

        do {
            try pipelineState = device.makeRenderPipelineState(
            descriptor: pipelineDesc)
        } catch {
            print("ParticleSystem Pipeline: Creating pipeline state failed")
        }
        
        let computeFunc = library.makeFunction(name: "particle_update")
        do {
            try computePipelineState = device.makeComputePipelineState(function: computeFunc!)
        } catch {
            print("Pipeline: Creating pipeline state failed")
        }

        particlesBuffer = device.makeBuffer(
            length: MemoryLayout<Particle>.stride,
            options: dynamicBufferResourceOption)!
        
        vertexBuffer = device.makeBuffer(
            length: MemoryLayout<float2>.stride * numVerticesPerParticle,
            options: staticBufferResourceOption)!
        indexBuffer = device.makeBuffer(
            length: MemoryLayout<UInt16>.stride * numVerticesPerParticle * 3,
            options: staticBufferResourceOption)!

        // The shared buffers used to update the GPUs buffers
        positionBuffer = device.makeBuffer(
            length: MemoryLayout<float2>.stride,
            options: dynamicBufferResourceOption)!
        radiusBuffer = device.makeBuffer(
            length: MemoryLayout<Float>.stride,
            options: dynamicBufferResourceOption)!
        colorBuffer = device.makeBuffer(
            length: MemoryLayout<float4>.stride,
            options: dynamicBufferResourceOption)!

        let textureDesc = MTLTextureDescriptor()
        textureDesc.height = Int(framebufferHeight)
        textureDesc.width = Int(framebufferWidth)
        textureDesc.sampleCount = 1
        textureDesc.textureType = .type2D
        textureDesc.pixelFormat = .bgra8Unorm
        textureDesc.resourceOptions = .storageModePrivate
        textureDesc.usage = .shaderRead
        inTexture = device.makeTexture(descriptor: textureDesc)!

        textureDesc.usage = .shaderWrite
        outTexture = device.makeTexture(descriptor: textureDesc)!

        finalTexture = device.makeTexture(descriptor: textureDesc)!

        buildVertices(numVertices: numVerticesPerParticle)
    }

    public func draw(
        view: MTKView,
        frameDescriptor: FrameDescriptor,
        commandBuffer: MTLCommandBuffer
        ) {

        if particleCount == 0 { return }

        commandBuffer.pushDebugGroup("ParticleSystem Draw")

        let renderPassDesc = MTLRenderPassDescriptor()
        renderPassDesc.colorAttachments[0].clearColor = frameDescriptor.clearColor
        renderPassDesc.colorAttachments[0].texture = inTexture
        renderPassDesc.colorAttachments[0].loadAction = .clear
        renderPassDesc.colorAttachments[0].storeAction = .store

        renderPassDesc.colorAttachments[1].clearColor = frameDescriptor.clearColor
        renderPassDesc.colorAttachments[1].texture = finalTexture
        renderPassDesc.colorAttachments[1].loadAction = .clear
        renderPassDesc.colorAttachments[1].storeAction = .store

        var renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc)!

        renderEncoder.pushDebugGroup("Draw particles (off-screen)")
        renderEncoder.setRenderPipelineState(pipelineState!)
        renderEncoder.setTriangleFillMode(frameDescriptor.fillMode)

        // Rebuild arrays
        for i in 0 ..< particles.count {
            positions[i] = particles[i].position
        }

        updateGPUBuffers(commandBuffer: commandBuffer)

        renderEncoder.setVertexBytes(&viewportSize,
                                     length: MemoryLayout<float2>.stride,
                                     index: BufferIndex.ViewportSizeIndex.rawValue)

        renderEncoder.setVertexBuffer(vertexBuffer,
                                      offset: 0,
                                      index: BufferIndex.VertexIndex.rawValue)

        renderEncoder.setVertexBuffer(positionBuffer,
                                      offset: 0,
                                      index: BufferIndex.PositionIndex.rawValue)

        renderEncoder.setVertexBuffer(radiusBuffer,
                                      offset: 0,
                                      index: BufferIndex.RadiusIndex.rawValue)

        renderEncoder.setVertexBuffer(colorBuffer,
                                      offset: 0,
                                      index: BufferIndex.ColorIndex.rawValue)

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

            blurKernel.encode(
                commandBuffer: commandBuffer,
                sourceTexture: inTexture,
                destinationTexture: outTexture
                )

            quad.mix(
                commandBuffer: commandBuffer,
                inputTexture1: inTexture,
                inputTexture2: outTexture,
                outTexture: finalTexture,
                sigma: 5.0
                )

            // quad.pixelate(
            // commandBuffer: commandBuffer,
            // inputTexture: inTexture,
            // outputTexture: finalTexture,
            // sigma: blurStrength
            // )

            renderEncoder.popDebugGroup()
        }

        let viewRenderPassDesc = view.currentRenderPassDescriptor

        if viewRenderPassDesc != nil {

            renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: viewRenderPassDesc!)!

            renderEncoder.pushDebugGroup("Draw particles (on-screen)")

            quad.draw(renderEncoder: renderEncoder, texture: finalTexture)

            renderEncoder.popDebugGroup()
            renderEncoder.endEncoding()

            commandBuffer.popDebugGroup()
        }
    }

    public func update(commandBuffer: MTLCommandBuffer) {

        if isPaused { return }

        if shouldUpdate {
            buildVertices(numVertices: numVerticesPerParticle)
            shouldUpdate = false
        }

        if enableCollisions && particles.count > 1 {

            var motionParam = MotionParam()
            motionParam.deltaTime = 1/60

            var computeParam = ComputeParam()
            computeParam.computeDeviceOption = gComputeDeviceOption
            computeParam.isMultithreaded = true
            computeParam.preferredThreadCount = 8
            computeParam.treeOption = .quadtree

            particles = collisionDetection.runTimeStep(
                commandBuffer: commandBuffer,
                collidables: particles,
                motionParam: motionParam,
                computeParam: computeParam)
        }
        
        
        // Update particles positions
//        updateParticles(commandBuffer: commandBuffer)
    }

    public func setVerticesPerParticle(num: Int) {

        numVerticesPerParticle = num
        shouldUpdate = true
    }

    private func buildVertices(numVertices: Int) {

        precondition(numVertices >= 3, "Can't draw anything with less than 3 vertices")

        // Clear previous values
        vertices.removeAll()
        indices.removeAll()

        vertices.reserveCapacity(numVertices)
        indices.reserveCapacity(numVertices)

        // Add indices
        for num in 0 ..< numVertices - 2 {
            indices.append(UInt16(0))
            indices.append(UInt16(num + 1))
            indices.append(UInt16(num + 2))
        }

        // Add vertices
        for num in 0 ..< numVertices {
            let cont = Float(num) * Float.pi * 2 / Float(numVertices)
            vertices.append(float2(cos(cont), sin(cont)))
        }

        // Update the GPU buffers
        vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<float2>.stride * vertices.count,
            options: staticBufferResourceOption)!

        indexBuffer = device.makeBuffer(
            bytes: indices,
            length: MemoryLayout<UInt16>.stride * indices.count,
            options: staticBufferResourceOption)!
    }

    private func updateGPUBuffers(commandBuffer: MTLCommandBuffer) {

        // Reallocate more if needed
        if particleCount > particlesAllocatedCount {

            // Update the allocated particle count
            particlesAllocatedCount = particleCount

            // Update the size of the GPU buffers
            positionBuffer = device.makeBuffer(
                length: particlesAllocatedCount * MemoryLayout<float2>.stride,
                options: dynamicBufferResourceOption)!

            radiusBuffer = device.makeBuffer(
                length: particlesAllocatedCount * MemoryLayout<Float>.stride,
                options: dynamicBufferResourceOption)!

            colorBuffer = device.makeBuffer(
                length: particlesAllocatedCount * MemoryLayout<float4>.stride,
                options: dynamicBufferResourceOption)!
            
            particlesBuffer = device.makeBuffer(
                length: particlesAllocatedCount * MemoryLayout<Particle>.stride,
                options: dynamicBufferResourceOption)!
        }
        
        positionBuffer.contents().copyMemory(
            from: &positions,
            byteCount: particlesAllocatedCount * MemoryLayout<float2>.stride)

        radiusBuffer.contents().copyMemory(
            from: &radii,
            byteCount: particlesAllocatedCount * MemoryLayout<Float>.stride)

        colorBuffer.contents().copyMemory(
            from: &colors,
            byteCount: particlesAllocatedCount * MemoryLayout<float4>.stride)

    }
    
    
    private func updateParticles(commandBuffer: MTLCommandBuffer) {
        
        commandBuffer.pushDebugGroup("Particles Update")
        
        let computeEncoder = commandBuffer.makeComputeCommandEncoder()
        
        computeEncoder?.setComputePipelineState(computePipelineState!)
        
        // Make sure to update the buffers before computing
        updateGPUBuffers(commandBuffer: commandBuffer)

        // Copy the CPU buffers back to the GPU
        particlesBuffer.contents().copyMemory(
            from: &particles,
            byteCount: particlesAllocatedCount * MemoryLayout<Particle>.stride)
        
        
        computeEncoder?.setBuffer(particlesBuffer,
                                  offset: 0,
                                  index: BufferIndex.ParticlesIndex.rawValue)


        var motionParam = MotionParam()
        motionParam.deltaTime = 1/60
        
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
        
        let recommendedThreadGroupWidth = (particles.count + threadGroupCount.width - 1) / threadGroupCount.width
        
        let threadGroups = MTLSize(
            width: recommendedThreadGroupWidth,
            height: 1,
            depth: 1)
        
        computeEncoder?.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCount)
        
        // Finish
        computeEncoder?.endEncoding()
        commandBuffer.popDebugGroup()
    }

    public func eraseParticles() {

        positions.removeAll()
        radii.removeAll()
        colors.removeAll()

        particles.removeAll()

        particlesAllocatedCount = 0

        particleCount = 0
    }

    public func addParticleWith(position: float2, color: float4, radius: Float) {

        var vel = float2(0)
        if hasInitialVelocity {
            vel = (randFloat2(-5, 5))
        }

        self.positions.append(position)
        self.radii.append(radius)
        self.colors.append(color)

        self.particleCount += 1

        var p = Particle()
        p.position = position
        p.velocity = vel
        p.radius = radius
        p.mass = Float.pi * radius * radius
        particles.append(p)
    }
}
