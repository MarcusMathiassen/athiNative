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

    ///////////////////
    // Simulation
    ///////////////////

    struct Particle : Collidable {
        var position: float2 = float2(0)
        var velocity: float2 = float2(0)
        var radius: Float = 0
        var mass: Float = 0
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

    public func updateParticlesGPU(commandBuffer: MTLCommandBuffer) {

        if particleCount == 0 { return }

        commandBuffer.pushDebugGroup("Particle GPU Update")

        // Make the encoder
        let computeEncoder = commandBuffer.makeComputeCommandEncoder()

        // Set the pipelinestate
        computeEncoder?.setComputePipelineState(computeParticleUpdatePipelineState!)

        // Update gravity
        if enableGravity {
            if useAccelerometerAsGravity {
                tempGravityForce = float2(accelerometer.x, accelerometer.y)
                } else {
                    tempGravityForce.y = gravityForce
                }
                } else {
                    tempGravityForce *= 0
                }

        // Set the buffers
        var simParam = SimParam()
        simParam.particle_count = Int32(particleCount)
        simParam.gravity_force = tempGravityForce
        simParam.viewport_size = viewportSize
        simParam.delta_time = 1/60
        simParam.gravity_well_point = mousePos
        simParam.gravity_well_force = (gMouseOption == MouseOption.Drag) ? 1e3 : 0
        simParam.enable_collisions = enableCollisions
        simParam.enable_border_collisions = enableBorderCollision
        simParam.should_repel = shouldRepel

        computeEncoder?.setBytes(&simParam,
            length: MemoryLayout<SimParam>.stride,
            index: BufferIndex.SimParamIndex.rawValue)

        computeEncoder?.setBytes(&collisionComparisons,
            length: MemoryLayout<UInt>.stride,
            index: BufferIndex.ComparisonIndex.rawValue)

        computeEncoder?.setBuffer(positionBuffer,
            offset: 0,
            index: BufferIndex.PositionIndex.rawValue)

        computeEncoder?.setBuffer(velocityBuffer,
            offset: 0,
            index: BufferIndex.VelocityIndex.rawValue)

        computeEncoder?.setBuffer(radiusBuffer,
            offset: 0,
            index: BufferIndex.RadiusIndex.rawValue)

        computeEncoder?.setBuffer(massBuffer,
            offset: 0,
            index: BufferIndex.MassIndex.rawValue)

        // Compute kernel threadgroup size
        let threadExecutionWidth = (computeParticleUpdatePipelineState?.threadExecutionWidth)!

        // A one dimensional thread group Swift to pass Metal a one dimensional array
        let threadGroupCount = MTLSize(
            width: threadExecutionWidth,
            height: 1,
            depth: 1)

        let recommendedThreadGroupWidth = (particleCount + threadGroupCount.width - 1) / threadGroupCount.width

        let threadGroups = MTLSize(
            width: recommendedThreadGroupWidth,
            height: 1,
            depth: 1)

        computeEncoder?.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCount)

        // print("Particle GPU Update threadGroupsCount", threadGroupCount)
        // print("Particle GPU Update threadGroups", threadGroups)

        // Finish
        computeEncoder?.endEncoding()
        commandBuffer.popDebugGroup()
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

        updateGPUBuffers(commandBuffer: commandBuffer)

        var simParam = SimParam()
        simParam.viewport_size = viewportSize

        renderEncoder.setVertexBytes(&simParam,
            length: MemoryLayout<SimParam>.stride,
            index: BufferIndex.SimParamIndex.rawValue)

        renderEncoder.setVertexBuffer(vertexBuffer,
            offset: 0,
            index: BufferIndex.VertexIndex.rawValue)
        renderEncoder.setVertexBuffer(colorBuffer,
            offset: 0,
            index: BufferIndex.ColorIndex.rawValue)

        renderEncoder.setVertexBuffer(positionBuffer,
            offset: 0,
            index: BufferIndex.PositionIndex.rawValue)
        renderEncoder.setVertexBuffer(radiusBuffer,
            offset: 0,
            index: BufferIndex.RadiusIndex.rawValue)

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

            commandBuffer.addCompletedHandler { (_) in
                self.bufferSemaphore.signal()
            }
        }
    }

    private func updateGPUBuffers(commandBuffer: MTLCommandBuffer) {

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
            positionBuffer = device.makeBuffer(
                length: particleCount * MemoryLayout<float2>.stride,
                options: dynamicBufferResourceOption)!
            velocityBuffer = device.makeBuffer(
                length: particleCount * MemoryLayout<float2>.stride,
                options: dynamicBufferResourceOption)!
            radiusBuffer = device.makeBuffer(
                length: particleCount * MemoryLayout<Float>.stride,
                options: dynamicBufferResourceOption)!
            massBuffer = device.makeBuffer(
                length: particleCount * MemoryLayout<Float>.stride,
                options: dynamicBufferResourceOption)!
            colorBuffer = device.makeBuffer(
                length: particleCount * MemoryLayout<float4>.stride,
                options: dynamicBufferResourceOption)!

            // Copy the CPU buffers back to the GPU
            positionBuffer.contents().copyMemory(
                from: &position,
                byteCount: particleCount * MemoryLayout<float2>.stride)
            velocityBuffer.contents().copyMemory(
                from: &velocity,
                byteCount: particleCount * MemoryLayout<float2>.stride)
            radiusBuffer.contents().copyMemory(
                from: &radius,
                byteCount: particleCount * MemoryLayout<Float>.stride)
            massBuffer.contents().copyMemory(
                from: &mass,
                byteCount: particleCount * MemoryLayout<Float>.stride)
            colorBuffer.contents().copyMemory(
                from: &color,
                byteCount: particleCount * MemoryLayout<float4>.stride)

            // Update the allocated particle count
            particlesAllocatedCount = particleCount

        }
    }

    public func update() {

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
                collidables: particles,
                motionParam: motionParam,
                computeParam: computeParam)
            
            for i in 0 ..< particles.count {
                position[i] = particles[i].position
                velocity[i] = particles[i].velocity
            }
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
    
    public func colorParticles(IDs: [Int], color: float4) {
        
        for pid in IDs {
            self.color[pid] = color
        }
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
        
        self.particles.append(p)
    }

    public func goTowardsPoint(_ point: float2, particleIDs: [Int]) {

        for id in particleIDs {
            velocity[id] = gravityWell(particleID: id, point: point)
        }
    }

    public func gravityWell(particleID: Int, point: float2) -> float2 {

        let p1 = position[particleID]
        let p2 = point
        let m1 = mass[particleID]
        let m2 = Float(1e11)

        let dp = p2 - p1

        let d = sqrt(dp.x * dp.x + dp.y * dp.y)

        let angle = atan2(dp.y, dp.x)
        let G = Float(kGravitationalConstant)
        let F = G * m1 * m2 / d * d

        let nX = F * cos(angle)
        let nY = F * sin(angle)

        return float2(nX, nY) + velocity[particleID]
    }

    /**
     Returns an array of ids that fit inside the circle
     */
     public func getParticlesInCircle(position: float2, radius: Float) -> [Int] {
        var ids: [Int] = []

//        // Brute-force
//        for pid in 0 ..< particleCount {
//
//            let bID = id[pid]
//
//            if collisionCheck(bID, position: position, radius: radius) {
//                ids.append(bID)
//            }
//        }

        return ids
    }
}
