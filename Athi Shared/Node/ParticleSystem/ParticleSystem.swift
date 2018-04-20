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

protocol Drawable {
    func draw(renderEncoder: MTLRenderCommandEncoder)
    func buildVertices(count: Int) -> ([float2], [UInt16])
}

final class ParticleSystem {

    ///////////////////
    // Simulation
    ///////////////////

    struct Particle : Collidable, Drawable {
        
        var position: float2 = float2(0)
        var velocity: float2 = float2(0)
        var radius: Float = 0
        var mass: Float = 0
        
        func buildVertices(count: Int) -> ([float2], [UInt16]) {
            
            precondition(count < 3, "Can't draw anything with less than 3 vertices")
            
            var vertices: [float2] = []
            var indices: [UInt16] = []
            
            vertices.reserveCapacity(count)
            indices.reserveCapacity(count)
            
            // Add indices
            for num in 0 ..< count - 2 {
                indices.append(UInt16(0))
                indices.append(UInt16(num + 1))
                indices.append(UInt16(num + 2))
            }
            
            // Add vertices
            for num in 0 ..< count {
                let cont = Float(num) * Float.pi * 2 / Float(count)
                vertices.append(float2(cos(cont), sin(cont)))
            }
            
            return (vertices, indices)
        }
        
        func draw(renderEncoder: MTLRenderCommandEncoder) {
            
        }
    }
    
    private var particles: [Particle] = []

    var collisionDetection: CollisionDetection<Particle>

    public var particleCount: Int = 0 // Amount of particles

    //      Particle data structure
    var id:         [Int] = []
    var position:   [float2] = []
    var velocity:   [float2] = []
    var radius:     [Float] = []
    var mass:       [Float] = []
    var color:      [float4] = []

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
    private var listOfNodesOfIDs: [[Int]] = []

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
    var blurStrength: Float = 10
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
    var numVerticesPerParticle = 36
    private var quad: Quad
    private var device: MTLDevice
    private var vertexBuffer: MTLBuffer
    private var indexBuffer: MTLBuffer
    private var pipelineState: MTLRenderPipelineState?

    var inTexture: MTLTexture
    var outTexture: MTLTexture
    var finalTexture: MTLTexture

    private var computeParticleUpdatePipelineState: MTLComputePipelineState?

    private var positionBuffer: MTLBuffer
    private var velocityBuffer: MTLBuffer
    private var radiusBuffer: MTLBuffer
    private var massBuffer: MTLBuffer
    private var colorBuffer: MTLBuffer

    private var blurKernel: MPSImageGaussianBlur

    var bufferSemaphore = DispatchSemaphore(value: 0)

    private var collisionComparisons: UInt32 = 0

    init(device: MTLDevice) {
        self.device = device
        quad = Quad(device: device)


        collisionDetection = CollisionDetection<Particle>(device: device)

        blurKernel = MPSImageGaussianBlur(device: device, sigma: blurStrength)

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

        // Load the kernel function from the library
        let computeParticleUpdateFunc = library.makeFunction(name: "particle_update")

        // Create a compute pipeline state
        do {
            try computeParticleUpdatePipelineState = device.makeComputePipelineState(
                function: computeParticleUpdateFunc!)
            } catch {
                print("Pipeline: Creating pipeline state failed")
            }

            particlesAllocatedCount = preAllocatedParticles
            vertexBuffer = device.makeBuffer(
                length: MemoryLayout<float2>.stride * numVerticesPerParticle,
                options: staticBufferResourceOption)!
            indexBuffer = device.makeBuffer(
                length: MemoryLayout<UInt16>.stride * numVerticesPerParticle * 3,
                options: staticBufferResourceOption)!

        // The shared buffers used to update the GPUs buffers
        positionBuffer = device.makeBuffer(
            length: MemoryLayout<float2>.stride * preAllocatedParticles,
            options: dynamicBufferResourceOption)!
        velocityBuffer = device.makeBuffer(
            length: MemoryLayout<float2>.stride * preAllocatedParticles,
            options: dynamicBufferResourceOption)!
        radiusBuffer = device.makeBuffer(
            length: MemoryLayout<Float>.stride * preAllocatedParticles,
            options: dynamicBufferResourceOption)!
        massBuffer = device.makeBuffer(
            length: MemoryLayout<Float>.stride * preAllocatedParticles,
            options: dynamicBufferResourceOption)!
        colorBuffer = device.makeBuffer(
            length: MemoryLayout<float4>.stride * preAllocatedParticles,
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

//        if particleCount == 0 { return }
//
//        commandBuffer.pushDebugGroup("ParticleSystem Draw")
//
//        let renderPassDesc = MTLRenderPassDescriptor()
//        renderPassDesc.colorAttachments[0].clearColor = frameDescriptor.clearColor
//        renderPassDesc.colorAttachments[0].texture = inTexture
//        renderPassDesc.colorAttachments[0].loadAction = .clear
//        renderPassDesc.colorAttachments[0].storeAction = .store
//
//        renderPassDesc.colorAttachments[1].clearColor = frameDescriptor.clearColor
//        renderPassDesc.colorAttachments[1].texture = finalTexture
//        renderPassDesc.colorAttachments[1].loadAction = .clear
//        renderPassDesc.colorAttachments[1].storeAction = .store
//
//        var renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc)!
//
//        renderEncoder.pushDebugGroup("Draw particles (off-screen)")
//        renderEncoder.setRenderPipelineState(pipelineState!)
//        renderEncoder.setTriangleFillMode(frameDescriptor.fillMode)
//
//        updateGPUBuffers(commandBuffer: commandBuffer)
//
//        renderEncoder.setVertexBytes(&viewportSize,
//                                     length: MemoryLayout<float2>.stride,
//                                     index: BufferIndex.ViewportSizeIndex.rawValue)
//
//        renderEncoder.setVertexBuffer(collidableBuffer,
//                                      offset: 0,
//                                      index: BufferIndex.CollidablesIndex.rawValue)
//
//        renderEncoder.setVertexBuffer(vertexBuffer,
//                                      offset: 0,
//                                      index: BufferIndex.VertexIndex.rawValue)
//
//        renderEncoder.setVertexBuffer(colorBuffer,
//                                      offset: 0,
//                                      index: BufferIndex.ColorIndex.rawValue)
//
//
//        renderEncoder.drawIndexedPrimitives(
//            type: .triangle,
//            indexCount: indices.count,
//            indexType: .uint16,
//            indexBuffer: indexBuffer,
//            indexBufferOffset: 0,
//            instanceCount: particleCount)
//
//        renderEncoder.popDebugGroup()
//        renderEncoder.endEncoding()
//
//        if enablePostProcessing {
//
//            renderEncoder.pushDebugGroup("Apply Post Processing")
//
//            blurKernel.encode(
//                commandBuffer: commandBuffer,
//                sourceTexture: inTexture,
//                destinationTexture: outTexture
//                )
//
//            quad.mix(
//                commandBuffer: commandBuffer,
//                inputTexture1: inTexture,
//                inputTexture2: outTexture,
//                outTexture: finalTexture,
//                sigma: 5.0
//                )
//
//            // quad.pixelate(
//            // commandBuffer: commandBuffer,
//            // inputTexture: inTexture,
//            // outputTexture: finalTexture,
//            // sigma: blurStrength
//            // )
//
//            renderEncoder.popDebugGroup()
//        }

//        let viewRenderPassDesc = view.currentRenderPassDescriptor
//
//        if viewRenderPassDesc != nil {
//
//            renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: viewRenderPassDesc!)!
//
//            renderEncoder.pushDebugGroup("Draw particles (on-screen)")
//
//            quad.draw(renderEncoder: renderEncoder, texture: finalTexture)
//
//            renderEncoder.popDebugGroup()
//            renderEncoder.endEncoding()
//
//            commandBuffer.popDebugGroup()
//
//            commandBuffer.addCompletedHandler { (_) in
//                self.bufferSemaphore.signal()
//            }
//        }
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
            computeParam.computeDeviceOption = .CPU
            computeParam.isMultithreaded = true
            computeParam.preferredThreadCount = 8
            computeParam.treeOption = .None

            particles = collisionDetection.runTimeStep(
                commandBuffer: commandBuffer,
                collidables: particles,
                motionParam: motionParam,
                computeParam: computeParam)
        }
    }

    public func setVerticesPerParticle(num: Int) {

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

    ////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////
    //////////  UTILITY
    ////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////
    
    
    public func eraseParticles() {
        
        position.removeAll()
        velocity.removeAll()
        mass.removeAll()
        radius.removeAll()
        color.removeAll()
        
        particlesAllocatedCount = 0
        
        particleCount = 0
    }

    public func addParticleWith(position: float2, color: float4, radius: Float) {

        self.id.append(particleCount)
        self.position.append(position)
        
        var vel = float2(0)
        if hasInitialVelocity {
            vel = (randFloat2(-5, 5))
        }

        self.velocity.append(vel)
        self.radius.append(radius)
        self.color.append(color)
        self.mass.append(Float.pi * radius * radius)

        self.particleCount += 1
        
        var p = Particle()
        p.position = position
        p.velocity = vel
        p.radius = radius
        p.mass = Float.pi * radius * radius
    }
}
