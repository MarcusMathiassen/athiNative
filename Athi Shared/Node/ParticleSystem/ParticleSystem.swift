//
//  ParticleSystem.swift
//  Athi
//
//  Created by Marcus Mathiassen on 04/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

// swiftlint:disable type_body_length function_body_length

import Metal
import MetalKit
import MetalPerformanceShaders

enum ParticleOption: String {
    case borderBound = "fc_has_borderBound"
    case intercollision = "fc_has_intercollision"
    case drawToTexture = "fc_has_drawToTexture"
    case lifetime = "fc_has_lifetime"
    case attractedToMouse = "fc_has_attractedToMouse"
    case homing = "fc_has_homing"
}

enum MissileOptions {
    case homing
}

enum EmitterOptions {
    case hasInterCollision
    case isBorderBound
    case createWithMouse
    case hasLifetime
}

/**
 Emmits particles.
 */
struct Emitter {

    /**
     The position to spawn from.
    */
    var spawnPoint: float2 = float2(0)

    /**
     The Emmit direction. Normalized.
    */
    var spawnDirection: float2 = float2(0)

    /**
     The initial velocity of each particle emmited
     */
    var spawnSpeed: Float = 0

    /**
     The amount of particles this emitter emmits.
    */
    private var particleCount: UInt32 = 0

    /**
     The maximum amount of particles this emitter can emmit.
    */
    var maxParticleCount: Int = 0

    var options: [EmitterOptions] = []
    var missleOptions: [MissileOptions] = []
}

final class ParticleSystem {

    var emitters: [Emitter] = []

    var maxParticles: Int

    var options: [ParticleOption] = []
    var computeDeviceOption: ComputeDeviceOption = .cpu

    public var particleCount: Int = 0

    var simParam: SimParam = SimParam()

    // Options
    var shouldRepel: Bool = false
    var enableMultithreading: Bool = false
    var enableBorderCollision: Bool = true
    var collisionEnergyLoss: Float = 0.98
    var gravityForce: Float = -0.0981
    var enableGravity: Bool = false
    var enableCollisions: Bool = false
    var useAccelerometerAsGravity: Bool = false
    var useQuadtree: Bool = true
    var hasInitialVelocity: Bool = true

    var isPaused: Bool = false

    private var tempGravityForce = float2(0)
    private var shouldUpdate: Bool = false

    ///////////////////
    // Rendering
    ///////////////////

    var enablePostProcessing: Bool = true
    var postProcessingSamples: Int = 1
    var blurStrength: Float = 10
    var preAllocatedParticles = 1
    private var particlesAllocatedCount: Int = 0

    private var gpuOnlyResourceOption: MTLResourceOptions = .storageModePrivate
    private var staticBufferResourceOption: MTLResourceOptions = .storageModeShared

    var particleColor = float4(1)
    var numVerticesPerParticle = 36
    var attractPoint = float2(0)
    private var quad: Quad
    private var device: MTLDevice

    // Buffers are shared between all Emitters in a ParticleSystem.
    //  Their size never changes, and must be set at compile time.
    private var positionsBuffer: MTLBuffer! = nil
    private var velocitiesBuffer: MTLBuffer! = nil
    private var radiiBuffer: MTLBuffer! = nil
    private var massesBuffer: MTLBuffer! = nil
    private var colorsBuffer: MTLBuffer! = nil
    private var isAlivesBuffer: MTLBuffer! = nil
    private var lifetimesBuffer: MTLBuffer! = nil
    private var gpuParticleCountBuffer: MTLBuffer! = nil

    private var vertices: [float2] = []
    private var indices: [UInt16] = []

    // Used for drawing polygon particles
    private var vertexBuffer: MTLBuffer! = nil
    private var indexBuffer: MTLBuffer! = nil

    private var pipelineState: MTLRenderPipelineState?
    private var computePipelineState: MTLComputePipelineState?

    var inTexture: MTLTexture! = nil
    var outTexture: MTLTexture! = nil
    var finalTexture: MTLTexture! = nil
    var pTexture: MTLTexture! = nil

    var bufferSemaphore = DispatchSemaphore(value: 1)

    var computeHelperFunctions: [String] = []
    var rawKernelString: String = ""

    private var usesTexture = false
    private var usesRadii = false
    private var usesMasses = false
    private var usesColors = false
    private var usesisAlives = false
    private var usesLifetimes = false

    private var hasInit = false

    init(device: MTLDevice,
         options: [ParticleOption] = [],
         maxParticles: Int = 1_000_000) {

        self.maxParticles = maxParticles
        self.options = options

        self.device = device
        quad = Quad(device: device)

        // Initalize our GPU buffers

        // Always needed
        positionsBuffer = device.makeBuffer(length: MemoryLayout<float2>.stride * maxParticles,
                                            options: gpuOnlyResourceOption)!
        velocitiesBuffer = device.makeBuffer(length: MemoryLayout<float2>.stride * maxParticles,
                                             options: gpuOnlyResourceOption)!
        gpuParticleCountBuffer = device.makeBuffer(length: MemoryLayout<UInt32>.stride,
                                                   options: gpuOnlyResourceOption)!

        usesRadii = true
        usesMasses = (options.contains(.intercollision) || options.contains(.attractedToMouse))
        usesColors = true
        usesisAlives = options.contains(.lifetime)
        usesLifetimes = usesisAlives
        usesTexture = options.contains(.drawToTexture)

        // Optional
        if usesRadii {
            radiiBuffer = device.makeBuffer(length: MemoryLayout<Float>.stride * maxParticles,
                                            options: gpuOnlyResourceOption)!
        }
        if usesMasses {
            massesBuffer = device.makeBuffer(length: MemoryLayout<Float>.stride * maxParticles,
                                             options: gpuOnlyResourceOption)!
        }
        if usesColors {
            colorsBuffer = device.makeBuffer(length: MemoryLayout<float4>.stride * maxParticles,
                                             options: gpuOnlyResourceOption)!
        }

        if usesisAlives {
            isAlivesBuffer = device.makeBuffer(length: MemoryLayout<Bool>.stride * maxParticles,
                                               options: gpuOnlyResourceOption)!
        }
        if usesLifetimes {
            lifetimesBuffer = device.makeBuffer(length: MemoryLayout<Float>.stride * maxParticles,
                                                options: gpuOnlyResourceOption)!
        }

        if !usesTexture {
            vertexBuffer = device.makeBuffer(length: MemoryLayout<float2>.stride * numVerticesPerParticle,
                                             options: staticBufferResourceOption)!
            indexBuffer = device.makeBuffer(length: MemoryLayout<UInt16>.stride * numVerticesPerParticle * 3,
                                            options: staticBufferResourceOption)!
        }

        particlesAllocatedCount = maxParticles

        let textureDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Renderer.pixelFormat,
            width: Int(framebufferWidth),
            height: Int(framebufferHeight),
            mipmapped: false)

        textureDesc.usage = .shaderRead
        inTexture = device.makeTexture(descriptor: textureDesc)!

        textureDesc.usage = .shaderWrite
        outTexture = device.makeTexture(descriptor: textureDesc)!
        finalTexture = device.makeTexture(descriptor: textureDesc)!
        pTexture = device.makeTexture(descriptor: textureDesc)!

        let constVals = MTLFunctionConstantValues()

        // Set all values to false first
        var falseVal = false

        constVals.setConstantValue(&falseVal, type: .bool, withName: ParticleOption.attractedToMouse.rawValue)
        constVals.setConstantValue(&falseVal, type: .bool, withName: ParticleOption.intercollision.rawValue)
        constVals.setConstantValue(&falseVal, type: .bool, withName: ParticleOption.borderBound.rawValue)
        constVals.setConstantValue(&falseVal, type: .bool, withName: ParticleOption.homing.rawValue)
        constVals.setConstantValue(&falseVal, type: .bool, withName: ParticleOption.lifetime.rawValue)
        constVals.setConstantValue(&falseVal, type: .bool, withName: ParticleOption.drawToTexture.rawValue)

        // Then set all found in options to true
        var trueVal = true
        for option in options {
            constVals.setConstantValue(&trueVal, type: .bool, withName: option.rawValue)
        }

        let library = device.makeDefaultLibrary()!
        var vertexFunc: MTLFunction! = nil
        do {
            try vertexFunc = library.makeFunction(name: "particle_vert", constantValues: constVals)
        } catch let error {
            print("Error: \(error)")
        }

        let fragFunc = library.makeFunction(name: "particle_frag")!

        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.label = "pipelineDesc"
        pipelineDesc.vertexFunction = vertexFunc
        pipelineDesc.fragmentFunction = fragFunc
        pipelineDesc.colorAttachments[0].pixelFormat = Renderer.pixelFormat
        pipelineDesc.colorAttachments[1].pixelFormat = Renderer.pixelFormat

        pipelineDesc.colorAttachments[0].isBlendingEnabled = true
        pipelineDesc.colorAttachments[0].rgbBlendOperation = .add
        pipelineDesc.colorAttachments[0].alphaBlendOperation = .add
        pipelineDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDesc.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        pipelineDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            try pipelineState = device.makeRenderPipelineState(descriptor: pipelineDesc)
        } catch let error {
            print("Error: \(error)")
        }

        var computeFunc: MTLFunction! = nil
        do {
            try computeFunc = library.makeFunction(name: "uber_compute", constantValues: constVals)
            computeFunc.label = "uber_compute"
        } catch let error {
            print("Error: \(error)")
        }
        do {
            try computePipelineState = device.makeComputePipelineState(function: computeFunc!)
        } catch let error {
            print("Error: \(error)")
        }

        buildVertices(numVertices: numVerticesPerParticle)
    }

    private func resetGPUParticleCount(commandBuffer: MTLCommandBuffer) {
        let blitCommandEncoder = commandBuffer.makeBlitCommandEncoder()!

        // Set GPU Particles count to 0
        var zero: UInt32 = 0
        let buff = device.makeBuffer(bytes: &zero, length: MemoryLayout<UInt32>.stride, options: .storageModeShared)!
        blitCommandEncoder.copy(
            from: buff,
            sourceOffset: 0,
            to: gpuParticleCountBuffer,
            destinationOffset: 0,
            size: MemoryLayout<UInt32>.stride
        )

        blitCommandEncoder.endEncoding()
    }


    /**
     Initilizes all GPU Bufferes
     */
    private func initGPUBuffers(commandBuffer: MTLCommandBuffer) {
        let blitCommandEncoder = commandBuffer.makeBlitCommandEncoder()!

        // Set GPU Particles count to 0
        var zero: UInt32 = 0
        let buff = device.makeBuffer(bytes: &zero, length: MemoryLayout<UInt32>.stride, options: .storageModeShared)!
        blitCommandEncoder.copy(
            from: buff,
            sourceOffset: 0,
            to: gpuParticleCountBuffer,
            destinationOffset: 0,
            size: MemoryLayout<UInt32>.stride
        )

//        if usesisAlives {
//            // Set all isAlives to true
//            var trueVals = [Bool](repeating: true, count: maxParticles)
//            let buffe = device.makeBuffer(bytes: &trueVals,
//                                          length: MemoryLayout<Bool>.stride * maxParticles,
//                                          options: .storageModeShared)!
//            blitCommandEncoder.copy(
//                from: buffe,
//                sourceOffset: 0,
//                to: isAlivesBuffer,
//                destinationOffset: 0,
//                size: MemoryLayout<Bool>.stride * maxParticles
//            )
//        }
        blitCommandEncoder.endEncoding()
    }

    public func addEmitter(_ emitter: Emitter) {
        emitters.append(emitter)
    }

    public func draw(view: MTKView, frameDescriptor: FrameDescriptor, commandBuffer: MTLCommandBuffer) {

        if particleCount == 0 { return }

        if !hasInit {
            initGPUBuffers(commandBuffer: commandBuffer)
            hasInit = true
        }

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

        if !usesTexture {

            if shouldUpdate {
                buildVertices(numVertices: numVerticesPerParticle)
                shouldUpdate = false
            }

            renderEncoder.setVertexBuffer(positionsBuffer, offset: 0, index: BufferIndex.bf_positions_index.rawValue)
            renderEncoder.setVertexBuffer(radiiBuffer, offset: 0, index: BufferIndex.bf_radii_index.rawValue)
            renderEncoder.setVertexBuffer(colorsBuffer, offset: 0, index: BufferIndex.bf_colors_index.rawValue)
            renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: BufferIndex.bf_vertices_index.rawValue)
            if usesLifetimes {
                 renderEncoder.setVertexBuffer(lifetimesBuffer,
                                               offset: 0,
                                               index: BufferIndex.bf_lifetimes_index.rawValue)
            }
            renderEncoder.setVertexBytes(&viewportSize, length: MemoryLayout<float2>.stride,
                                         index: BufferIndex.bf_viewportSize_index.rawValue)

            renderEncoder.setTriangleFillMode(frameDescriptor.fillMode)

            renderEncoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: indices.count,
                indexType: .uint16,
                indexBuffer: indexBuffer,
                indexBufferOffset: 0,
                instanceCount: particleCount
            )
        }

        renderEncoder.popDebugGroup()
        renderEncoder.endEncoding()

        if enablePostProcessing {

            renderEncoder.pushDebugGroup("Apply Post Processing")

            let blurKernel = MPSImageGaussianBlur(device: device, sigma: blurStrength)
            blurKernel.encode(
                commandBuffer: commandBuffer,
                sourceTexture: usesTexture ? pTexture : inTexture,
                destinationTexture: outTexture
                )

            quad.mix(
                commandBuffer: commandBuffer,
                inputTexture1: usesTexture ? pTexture : inTexture,
                inputTexture2: outTexture,
                outTexture: finalTexture,
                sigma: 5.0
                )

            renderEncoder.popDebugGroup()
        } else if usesTexture {
            quad.mix(
                commandBuffer: commandBuffer,
                inputTexture1: pTexture,
                inputTexture2: outTexture,
                outTexture: finalTexture,
                sigma: 5.0
            )
        }

        let viewRenderPassDesc = view.currentRenderPassDescriptor
        if viewRenderPassDesc != nil {

            if options.contains(.drawToTexture) {
                viewRenderPassDesc?.colorAttachments[1].clearColor = frameDescriptor.clearColor
                viewRenderPassDesc?.colorAttachments[1].texture = pTexture
                viewRenderPassDesc?.colorAttachments[1].loadAction = .clear
                viewRenderPassDesc?.colorAttachments[1].storeAction = .store
            }

            renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: viewRenderPassDesc!)!
            renderEncoder.pushDebugGroup("Draw particles (on-screen)")

            quad.draw(renderEncoder: renderEncoder, texture: finalTexture)

            renderEncoder.popDebugGroup()
            renderEncoder.endEncoding()
            commandBuffer.popDebugGroup()
        }
    }

    public func drawDebug(color: float4,
                          view: MTKView,
                          frameDescriptor: FrameDescriptor,
                          commandBuffer: MTLCommandBuffer) {
    }

    public func update(commandBuffer: MTLCommandBuffer,
                       computeDevice: ComputeDeviceOption) {

        if isPaused { return }

        switch computeDevice {
        case .cpu:
            break
        case .gpu:
            updateParticles(commandBuffer: commandBuffer)
        }
    }

    func customThreadgroupsPerGrid() -> MTLSize {
        let threadExecutionWidth = (computePipelineState?.threadExecutionWidth)!

        return MTLSize(width: particleCount / threadExecutionWidth, height: 1, depth: 1)
    }

    func customThreadsPerThreadgroup() -> MTLSize {
        let threadExecutionWidth = (computePipelineState?.threadExecutionWidth)!

        return MTLSize(width: threadExecutionWidth, height: 1, depth: 1)
    }

    private func updateParticles(commandBuffer: MTLCommandBuffer) {

        if particleCount == 0 { return }

        commandBuffer.pushDebugGroup("Particles Update")

        if simParam.clearParticles { resetGPUParticleCount(commandBuffer: commandBuffer) }

        let computeEncoder = commandBuffer.makeComputeCommandEncoder()!

        computeEncoder.setComputePipelineState(computePipelineState!)

        computeEncoder.setBuffer(positionsBuffer, offset: 0, index: BufferIndex.bf_positions_index.rawValue)
        computeEncoder.setBuffer(velocitiesBuffer, offset: 0, index: BufferIndex.bf_velocities_index.rawValue)
        computeEncoder.setBuffer(gpuParticleCountBuffer, offset: 0,
                                 index: BufferIndex.bf_gpuParticleCount_index.rawValue)

        if usesRadii {
            computeEncoder.setBuffer(radiiBuffer, offset: 0, index: BufferIndex.bf_radii_index.rawValue)
        }
        if usesMasses {
            computeEncoder.setBuffer(massesBuffer, offset: 0, index: BufferIndex.bf_masses_index.rawValue)
        }
        if usesColors {
            computeEncoder.setBuffer(colorsBuffer, offset: 0, index: BufferIndex.bf_colors_index.rawValue)
        }
        if usesisAlives {
            computeEncoder.setBuffer(isAlivesBuffer, offset: 0, index: BufferIndex.bf_isAlives_index.rawValue)
        }
        if usesLifetimes {
            computeEncoder.setBuffer(lifetimesBuffer, offset: 0, index: BufferIndex.bf_lifetimes_index.rawValue)
        }

        if usesTexture { computeEncoder.setTexture(pTexture, index: 0) }

        var motionParam = MotionParam()
        motionParam.deltaTime = 1/60
        computeEncoder.setBytes(&motionParam,
                                 length: MemoryLayout<MotionParam>.stride,
                                 index: BufferIndex.bf_motionParam_index.rawValue)

        simParam.particleCount = UInt32(particleCount)
        simParam.viewportSize = viewportSize
        simParam.attractPoint = attractPoint
        simParam.mousePos = mousePos
        simParam.currentTime = Float(getTime())
        simParam.gravityForce = enableGravity ? float2(0, gravityForce) : float2(0)
        computeEncoder.setBytes(&simParam,
                                 length: MemoryLayout<SimParam>.stride,
                                 index: BufferIndex.bf_simParam_index.rawValue)
        // Reset simParams
        simParam.clearParticles = false
        simParam.shouldAddParticle = false
        simParam.newParticlePosition = mousePos

        // Compute kernel threadgroup size
        let threadExecutionWidth = (computePipelineState?.threadExecutionWidth)!

        // A one dimensional thread group Swift to pass Metal a one dimensional array
        let threadGroupCount = MTLSize(width: threadExecutionWidth, height: 1, depth: 1)
        let threadGroups = MTLSize(width: (particleCount + threadGroupCount.width - 1) / threadGroupCount.width,
                                   height: 1,
                                   depth: 1)

        computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCount)

        // Finish
        computeEncoder.endEncoding()
        commandBuffer.popDebugGroup()
    }

    public func eraseParticles() {
        self.particleCount = 0
        self.simParam.clearParticles = true
    }

    public func addParticleWith(position: float2, color: float4, radius: Float) {

        if self.particleCount == self.maxParticles { return }

        self.particleCount += 1

        self.simParam.shouldAddParticle = true
        self.simParam.newParticlePosition = position
        self.simParam.newParticleVelocity = hasInitialVelocity ? float2(-5, 5) : float2(0)
        self.simParam.newParticleRadius = radius
        self.simParam.newParticleMass = Float.pi * radius * radius * radius
        self.simParam.newParticleColor = color
        self.simParam.newParticleLifetime = 3
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
}
