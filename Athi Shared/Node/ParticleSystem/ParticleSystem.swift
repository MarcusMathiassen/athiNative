//
//  ParticleSystem.swift
//  Athi
//
//  Created by Marcus Mathiassen on 04/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

// swiftlint:disable type_body_length function_body_length identifier_name

import Metal
import MetalKit
import MetalPerformanceShaders // MPSImageGaussianBlur

enum ParticleOption: String {
    case borderBound = "fc_has_borderBound"
    case intercollision = "fc_has_intercollision"
    case drawToTexture = "fc_has_drawToTexture"
    case lifetime = "fc_has_lifetime"
    case attractedToMouse = "fc_has_attractedToMouse"
    case homing = "fc_has_homing"
    case turbulence = "fc_has_turbulence"
    case canAddParticles = "fc_has_canAddParticles"
    case respawns = "fc_has_respawns"
}

enum EmitterOptions {
    case borderBound
    case intercollision
    case drawToTexture
    case lifetime
    case attractedToMouse
    case homing
    case turbulenceader
    case canAddParticles
    case respawns
}

struct PSEmitterDescriptor {
    var isActive: Bool = false
    var spawnPoint: float2 = float2(0, 0)
    var spawnDirection: float2 = float2(0, 1)
    var spawnRate: Float = 10.0
    var particleSpeed: Float = 5.0
    var particleColor: float4 = float4(1)
    var particleSize: Float = 1.0
    var particleLifetime: Float = 1.0
    var mozzleSpread: Float = 1.0
    var options: [EmitterOptions] = [.lifetime, .respawns]
}

/**
    A particle system consist of N number of emitters
     sharing a fixed size particle pool between them.
*/
final class ParticleSystem {

    /**
        A list of all emitters in the ParticleSystem.
    */
    var emitters: [Emitter] = []
    
    var emitterIndices: [UInt16] = []
    
    /**
        The maximum amount of emitters this ParticleSystem can use.
    */
    private var maxEmitterCount: Int

    private var emittersToAddCount: Int = 0

    /**
        Maximum amount of particles that can be emitted at the same time.
    */
    var maxParticles: Int

    /**
        A list of all available features for emitters
    */
    var options: [ParticleOption] = []

    /**
        The compute device to use.
    */
    var computeDeviceOption: ComputeDeviceOption = .gpu

    /**
        Number of active particles.
    */
    public var particleCount: Int = 0

    var globalParam: GlobalParam = GlobalParam()
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
    private var emittersBuffer: MTLBuffer! = nil
    private var emitterIndicesBuffer: MTLBuffer! = nil

    private var positionsBuffer: MTLBuffer! = nil
    private var velocitiesBuffer: MTLBuffer! = nil
    private var radiiBuffer: MTLBuffer! = nil
    private var massesBuffer: MTLBuffer! = nil
    private var colorsBuffer: MTLBuffer! = nil
    private var isAlivesBuffer: MTLBuffer! = nil
    private var lifetimesBuffer: MTLBuffer! = nil
    private var gpuParticleCountBuffer: MTLBuffer! = nil

    // Turbulence buffers
    private var seedBuffer: MTLBuffer! = nil
    private var fieldNodesBuffer: MTLBuffer! = nil

    private var vertices: [float2] = []
    private var indices: [UInt16] = []

    // Used for drawing polygon particles
    private var vertexBuffer: MTLBuffer! = nil
    private var indexBuffer: MTLBuffer! = nil

    private var pipelineState: MTLRenderPipelineState?
    private var computePipelineState: MTLComputePipelineState?
    private var initComputePipelineState: MTLComputePipelineState?
    private var basicComputePipelineState: MTLComputePipelineState?

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
    private var usesSeedBuffer = false
    private var usesFieldNodes = false

    private var shouldAddEmitter = false
    private var hasInit = false
    private var clearParticles = true

    public func makeEmitter(descriptor: PSEmitterDescriptor) -> Emitter {
        var emitter = Emitter()
        emitter.particleCount = uint(Int32(descriptor.spawnRate / descriptor.particleLifetime))
        emitter.lifetime = descriptor.particleLifetime
        emitter.position = descriptor.spawnPoint
        emitter.size = descriptor.particleSize
        emitter.color = descriptor.particleColor
        emitter.direction = descriptor.spawnDirection

        emitter.speed = 5
        emitter.spread = descriptor.mozzleSpread

        emitter.isActive = descriptor.isActive
        emitter.hasCanAddParticles = descriptor.options.contains(.canAddParticles)
        emitter.hasHoming = descriptor.options.contains(.homing)
        emitter.hasBorderBound = descriptor.options.contains(.borderBound)
        emitter.hasLifetime = descriptor.options.contains(.lifetime)
        emitter.hasIntercollision = descriptor.options.contains(.intercollision)
        emitter.hasRespawns = descriptor.options.contains(.respawns)

        return emitter
    }

    init(device: MTLDevice,
         options: [ParticleOption] = [],
         maxParticles: Int = 1_000_000) {

        self.maxParticles = maxParticles
        self.maxEmitterCount = maxParticles / 10

        self.options = options

        self.device = device
        quad = Quad(device: device)

        emitterIndices = [UInt16](repeating: 0, count: maxParticles)

        // Initalize our GPU buffers
        // Always needed
        emittersBuffer = device.makeBuffer(length: MemoryLayout<Emitter>.stride * maxEmitterCount,
                                            options: .storageModeShared)!
        emitterIndicesBuffer = device.makeBuffer(length: MemoryLayout<UInt16>.stride * maxParticles,
                                           options: gpuOnlyResourceOption)!

        positionsBuffer = device.makeBuffer(length: MemoryLayout<float2>.stride * maxParticles,
                                            options: gpuOnlyResourceOption)!
        velocitiesBuffer = device.makeBuffer(length: MemoryLayout<float2>.stride * maxParticles,
                                             options: gpuOnlyResourceOption)!
        gpuParticleCountBuffer = device.makeBuffer(length: MemoryLayout<UInt32>.stride,
                                                   options: gpuOnlyResourceOption)!

        self.usesRadii = true
        self.usesMasses = (options.contains(.intercollision) || options.contains(.attractedToMouse))
        self.usesColors = true
        self.usesisAlives = options.contains(.lifetime)
        self.usesLifetimes = usesisAlives
        self.usesTexture = options.contains(.drawToTexture)
        self.usesSeedBuffer = options.contains(.turbulence)
        self.usesFieldNodes = usesSeedBuffer

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

        if usesSeedBuffer {
            fieldNodesBuffer = device.makeBuffer(
                length: MemoryLayout<float2>.stride * Int(framebufferWidth) * Int(framebufferHeight),
                options: gpuOnlyResourceOption)!

            seedBuffer = device.makeBuffer(
                length: MemoryLayout<Int32>.stride * 512,
                options: gpuOnlyResourceOption)!
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
        var falseVals = [Bool](repeating: false, count: 9)
        constVals.setConstantValues(&falseVals, type: .bool, range: 0 ..< falseVals.count)

        // Then set all found in options to true
        var trueVal = true
        for option in options {
            constVals.setConstantValue(&trueVal, type: .bool, withName: option.rawValue)
        }

        print(constVals)

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

//        var computeFunc: MTLFunction! = nil
//        do {
//            try computeFunc = library.makeFunction(name: "uber_compute", constantValues: constVals)
//            computeFunc.label = "uber_compute"
//        } catch let error {
//            print("Error: \(error)")
//        }
//        do {
//            try computePipelineState = device.makeComputePipelineState(function: computeFunc!)
//        } catch let error {
//            print("Error: \(error)")
//        }

        var basicComputeFunc: MTLFunction! = nil
        do {
            try basicComputeFunc = library.makeFunction(name: "basic_update", constantValues: constVals)
            basicComputeFunc.label = "basic_update"
        } catch let error {
            print("Error: \(error)")
        }
        do {
            try basicComputePipelineState = device.makeComputePipelineState(function: basicComputeFunc!)
        } catch let error {
            print("Error: \(error)")
        }

        buildVertices(numVertices: numVerticesPerParticle)

        let byteF = ByteCountFormatter()
        byteF.allowedUnits = .useAll
        byteF.isAdaptive = true

        #if os(macOS)
        print(
            device.name,
            "allocated:",
            byteF.string(fromByteCount: Int64(device.currentAllocatedSize)),
            "of",
            byteF.string(fromByteCount: Int64(device.recommendedMaxWorkingSetSize))
            )
        #endif
    }

    private func clearGPUParticles(commandBuffer: MTLCommandBuffer) {
        let blitCommandEncoder = commandBuffer.makeBlitCommandEncoder()!

        // Set GPU Particles count to 0
        var val: UInt32 = 0
        let buff = device.makeBuffer(bytes: &val, length: MemoryLayout<UInt32>.stride, options: .storageModeShared)!
        blitCommandEncoder.copy(
            from: buff,
            sourceOffset: 0,
            to: gpuParticleCountBuffer,
            destinationOffset: 0,
            size: MemoryLayout<UInt32>.stride
        )


        var vas = [Float](repeating: -1.0, count: maxParticles)
        let buffi = device.makeBuffer(bytes: &vas,
                                      length: MemoryLayout<Float>.stride * maxParticles,
                                      options: .storageModeShared)!
        blitCommandEncoder.copy(
            from: buffi,
            sourceOffset: 0,
            to: lifetimesBuffer,
            destinationOffset: 0,
            size: MemoryLayout<Float>.stride * maxParticles
        )
        blitCommandEncoder.endEncoding()
    }
    private func setGPUParticleCount(commandBuffer: MTLCommandBuffer, value: Int) {
        let blitCommandEncoder = commandBuffer.makeBlitCommandEncoder()!

        // Set GPU Particles count to 0
        var val: UInt32 = UInt32(value)
        let buff = device.makeBuffer(bytes: &val, length: MemoryLayout<UInt32>.stride, options: .storageModeShared)!
        blitCommandEncoder.copy(
            from: buff,
            sourceOffset: 0,
            to: gpuParticleCountBuffer,
            destinationOffset: 0,
            size: MemoryLayout<UInt32>.stride
        )
        blitCommandEncoder.endEncoding()
    }

    private func updateGPUBuffers(commandBuffer: MTLCommandBuffer) {
        let blitCommandEncoder = commandBuffer.makeBlitCommandEncoder()!

        let newEmitterBuffer = device.makeBuffer(bytes: &emitters,
                                     length: MemoryLayout<Emitter>.stride * emitters.count,
                                     options: .storageModeShared)!
        blitCommandEncoder.copy(
            from: newEmitterBuffer,
            sourceOffset: 0,
            to: emittersBuffer,
            destinationOffset: 0,
            size: MemoryLayout<Emitter>.stride * emitters.count
        )
        blitCommandEncoder.endEncoding()
    }

    /**
        Adds an emitter to the particle system.
        Return an ID for future updates to the emitter.
    */
    public func addEmitter(_ emitter: inout Emitter) -> Int {
        if shouldAddEmitter { return -1 }
        if emitters.count+1 > maxEmitterCount ||
            Int(emitter.particleCount) + particleCount > maxParticles { return -1; }

        emitter.startIndex = UInt32(particleCount)

        let id = emitters.count
        emitters.append(emitter)

        // Increase the total amount of particles used
        particleCount += Int(emitter.particleCount)

        shouldAddEmitter = true
        emittersToAddCount += 1

        return id
    }

    public func draw(view: MTKView, frameDescriptor: FrameDescriptor, commandBuffer: MTLCommandBuffer) {

        if emitters.count == 0 { return }

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

    private func basic_update(commandBuffer: MTLCommandBuffer) {

        if emitters.count == 0 { return }
        if clearParticles {
            clearGPUParticles(commandBuffer: commandBuffer)
            clearParticles = false
        }

        if shouldAddEmitter {
            updateEmitterIndices(commandBuffer: commandBuffer)
            setGPUParticleCount(commandBuffer: commandBuffer, value: emitters.count)
            shouldAddEmitter = false
        }

        commandBuffer.pushDebugGroup("Particles Update")

        // Update emitter buffers
        emittersBuffer.contents().copyMemory(from: &emitters, byteCount: MemoryLayout<Emitter>.stride * emitters.count)

        let computeEncoder = commandBuffer.makeComputeCommandEncoder()!

        computeEncoder.setComputePipelineState(basicComputePipelineState!)

        var globalParam = GlobalParam()
        globalParam.attractPoint = attractPoint
        globalParam.currentTime = Float(getTime())
        globalParam.deltaTime = 1/60
        globalParam.emitterCount = UInt32(emitters.count)
        globalParam.mousePos = mousePos
        globalParam.gravityForce = enableGravity ? float2(0, gravityForce) : float2(0)
        globalParam.particleCount = UInt32(particleCount)
        globalParam.viewportSize = viewportSize

        computeEncoder.setBytes(&globalParam,
                                length: MemoryLayout<GlobalParam>.stride,
                                index: BufferIndex.bf_globalParam_index.rawValue)

        computeEncoder.setBuffer(emittersBuffer, offset: 0, index: BufferIndex.bf_emitters_index.rawValue)
        computeEncoder.setBuffer(emitterIndicesBuffer, offset: 0, index: BufferIndex.bf_emitter_indices_index.rawValue)

        computeEncoder.setBuffer(positionsBuffer, offset: 0, index: BufferIndex.bf_positions_index.rawValue)
        computeEncoder.setBuffer(velocitiesBuffer, offset: 0, index: BufferIndex.bf_velocities_index.rawValue)
        computeEncoder.setBuffer(radiiBuffer, offset: 0, index: BufferIndex.bf_radii_index.rawValue)
        computeEncoder.setBuffer(colorsBuffer, offset: 0, index: BufferIndex.bf_colors_index.rawValue)
        computeEncoder.setBuffer(isAlivesBuffer, offset: 0, index: BufferIndex.bf_isAlives_index.rawValue)
        computeEncoder.setBuffer(lifetimesBuffer, offset: 0, index: BufferIndex.bf_lifetimes_index.rawValue)

        if usesMasses {
            computeEncoder.setBuffer(massesBuffer, offset: 0, index: BufferIndex.bf_masses_index.rawValue)
        }

        // Reset frame by frame variables
        emittersToAddCount = 0

        // Compute kernel threadgroup size
        let threadExecutionWidth = (basicComputePipelineState?.threadExecutionWidth)!

        // A one dimensional thread group Swift to pass Metal a one dimensional array
        let threadGroupCount = MTLSize(width: threadExecutionWidth, height: 1, depth: 1)
        let threadGroups = MTLSize(
            width: (particleCount + threadGroupCount.width - 1) / threadGroupCount.width,
            height: 1,
            depth: 1)

        computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCount)

        // Finish
        computeEncoder.endEncoding()
        commandBuffer.popDebugGroup()
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
            basic_update(commandBuffer: commandBuffer)
        }
    }

    public func eraseParticles() {
        self.particleCount = 0
        self.clearParticles = true
        self.emitters.removeAll()
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

    private func updateEmitterIndices(commandBuffer: MTLCommandBuffer) {

        for emitterIndex in emitters.indices {
            var counter = emitters[emitterIndex].startIndex
            let amount = emitters[emitterIndex].startIndex + emitters[emitterIndex].particleCount
            for i in counter ..< amount {
                emitterIndices[Int(i)] = UInt16(emitterIndex)
            }
        }
        let blitCommandEncoder = commandBuffer.makeBlitCommandEncoder()!

        // Set GPU Particles count to 0
        let buff = device.makeBuffer(bytes: &emitterIndices,
                                     length: MemoryLayout<UInt16>.stride * maxParticles,
                                     options: .storageModeShared)!
        blitCommandEncoder.copy(
            from: buff,
            sourceOffset: 0,
            to: emitterIndicesBuffer,
            destinationOffset: 0,
            size: MemoryLayout<UInt16>.stride * maxParticles
        )
        blitCommandEncoder.endEncoding()
    }
}
