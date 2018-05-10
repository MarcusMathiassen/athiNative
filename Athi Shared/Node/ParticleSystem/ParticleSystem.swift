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
import MetalPerformanceShaders

enum ParticleOption: String {
    case borderBound = "fc_has_borderBound"
    case intercollision = "fc_has_intercollision"
    case drawToTexture = "fc_has_drawToTexture"
    case lifetime = "fc_has_lifetime"
    case attractedToMouse = "fc_has_attractedToMouse"
    case homing = "fc_has_homing"
    case turbulence = "fc_has_turbulence"
    case canAddParticles = "fc_has_canAddParticles"
}

enum MissileOptions {
    case homing
}

enum EmitterOptions {
    case borderBound
    case intercollision
    case drawToTexture
    case lifetime
    case attractedToMouse
    case homing
    case turbulence
    case canAddParticles
}

/**
 Emmits particles.
 */
struct Emitter {

    var id: Int = 0

    /**
     The position to spawn from.
    */
    var position: float2 = float2(0)

    /**
     The Emmit direction. Normalized.
    */
    var direction: float2 = float2(0)

    var size: Float = 5

    /**
     The initial velocity of each particle emmited
     */
    var speed: Float = 0

    var lifetime: Float = 1

    /**
     The initial velocity of each particle emmited
     */
    var spread: Float = 0

    var color: float4 = float4(1)

    /**
     The amount of particles this emitter emmits.
    */
    private var particleCount: UInt32 = 0

    /**
     The amount of particles this emitter can emmit.
    */
    var count: Int = 0

    var options: [EmitterOptions] = []
}


final class ParticleSystem {

    var emitters: [_Emitter] = []
    private var maxEmitterCount: Int

    // every emitter gets a piece of the pie

    var maxParticles: Int

    var options: [ParticleOption] = []
    var computeDeviceOption: ComputeDeviceOption = .cpu

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

    private var hasInit = false

    init(device: MTLDevice,
         options: [ParticleOption] = [],
         maxParticles: Int = 1_000_000) {

        self.maxParticles = maxParticles
        self.maxEmitterCount = 1000

        self.options = options

        self.device = device
        quad = Quad(device: device)

//        if !options.contains(.canAddParticles) {
//            self.particleCount = maxParticles
//        }

        // Initalize our GPU buffers
        // Always needed
        emittersBuffer = device.makeBuffer(length: MemoryLayout<_Emitter>.stride * maxEmitterCount,
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
        var falseVal = false

        constVals.setConstantValue(&falseVal, type: .bool, withName: ParticleOption.attractedToMouse.rawValue)
        constVals.setConstantValue(&falseVal, type: .bool, withName: ParticleOption.intercollision.rawValue)
        constVals.setConstantValue(&falseVal, type: .bool, withName: ParticleOption.borderBound.rawValue)
        constVals.setConstantValue(&falseVal, type: .bool, withName: ParticleOption.homing.rawValue)
        constVals.setConstantValue(&falseVal, type: .bool, withName: ParticleOption.lifetime.rawValue)
        constVals.setConstantValue(&falseVal, type: .bool, withName: ParticleOption.drawToTexture.rawValue)
        constVals.setConstantValue(&falseVal, type: .bool, withName: ParticleOption.canAddParticles.rawValue)
        constVals.setConstantValue(&falseVal, type: .bool, withName: ParticleOption.turbulence.rawValue)

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

        if !options.contains(.canAddParticles) {
            var initComputeFunc: MTLFunction! = nil
            do {
                try initComputeFunc = library.makeFunction(name: "init_buffers", constantValues: constVals)
                initComputeFunc.label = "init_buffers"
            } catch let error {
                print("Error: \(error)")
            }
            do {
                try initComputePipelineState = device.makeComputePipelineState(function: initComputeFunc!)
            } catch let error {
                print("Error: \(error)")
            }
        }

        if usesSeedBuffer {
            //----------------------------------
            //  Turbulence
            //----------------------------------
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
        
        var vas = [Bool](repeating: false, count: maxParticles)
        let buffi = device.makeBuffer(bytes: &vas,
                                     length: MemoryLayout<Bool>.stride * maxParticles,
                                     options: .storageModeShared)!
        blitCommandEncoder.copy(
            from: buffi,
            sourceOffset: 0,
            to: isAlivesBuffer,
            destinationOffset: 0,
            size: MemoryLayout<Bool>.stride * maxParticles
        )
        
        var vasee = [_Emitter](repeating: _Emitter(), count: maxParticles)
        let buffeei = device.makeBuffer(bytes: &vasee,
                                      length: MemoryLayout<_Emitter>.stride * maxEmitterCount,
                                      options: .storageModeShared)!
        blitCommandEncoder.copy(
            from: buffeei,
            sourceOffset: 0,
            to: emittersBuffer,
            destinationOffset: 0,
            size: MemoryLayout<_Emitter>.stride * maxEmitterCount
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

        blitCommandEncoder.endEncoding()

        if !options.contains(.canAddParticles) {
            self.simParam.newParticlePosition = viewportSize / 2
            self.simParam.newParticleVelocity = hasInitialVelocity ? float2(-5, 5) : float2(0)
            self.simParam.newParticleRadius = 5
            self.simParam.newParticleMass = Float.pi * 5 * 5
            self.simParam.newParticleColor = float4(1)
            self.simParam.newParticleLifetime = 1.0

            self.simParam.emitter_count = UInt32(emitters.count)

            commandBuffer.pushDebugGroup("GPU buffers init")

            // Update emitter buffers
            emittersBuffer.contents().copyMemory(from: &emitters, byteCount: MemoryLayout<_Emitter>.stride * emitters.count)

            let computeEncoder = commandBuffer.makeComputeCommandEncoder()!

            computeEncoder.setComputePipelineState(initComputePipelineState!)

            computeEncoder.setBuffer(emittersBuffer, offset: 0, index: BufferIndex.bf_emitters_index.rawValue)
            computeEncoder.setBuffer(emitterIndicesBuffer, offset: 0, index: BufferIndex.bf_emitter_indices_index.rawValue)

            computeEncoder.setBuffer(positionsBuffer, offset: 0, index: BufferIndex.bf_positions_index.rawValue)
            computeEncoder.setBuffer(velocitiesBuffer, offset: 0, index: BufferIndex.bf_velocities_index.rawValue)
            computeEncoder.setBuffer(gpuParticleCountBuffer,
                                     offset: 0,
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

            if usesSeedBuffer {
                computeEncoder.setBuffer(seedBuffer, offset: 0, index: BufferIndex.bf_seed_buffer_index.rawValue)
                computeEncoder.setBuffer(fieldNodesBuffer, offset: 0, index: BufferIndex.bf_field_nodes_index.rawValue)
            }

            if usesTexture { computeEncoder.setTexture(pTexture, index: 0) }

            simParam.particleCount = UInt32(particleCount)
            simParam.viewportSize = viewportSize
            simParam.attractPoint = attractPoint
            simParam.emitter_count = UInt32(emitters.count)
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
    }

    public func addEmitter(_ emitter: Emitter) -> Int {

        if particleCount + emitter.count > maxParticles {
           print("Max particle count reached.")
            return -1
        }

        var temp_emitter = _Emitter()
        temp_emitter.color = emitter.color
        temp_emitter.direction = emitter.direction
        temp_emitter.position = emitter.position

        let hasCanAddParticles = emitter.options.contains(.canAddParticles)
        temp_emitter.particle_count = hasCanAddParticles ? 0 : UInt32(emitter.count)

        temp_emitter.start_index = UInt32(particleCount)
        temp_emitter.end_index = temp_emitter.start_index + temp_emitter.particle_count

        temp_emitter.target_pos = attractPoint
        temp_emitter.max_particle_count = UInt32(emitter.count)
        temp_emitter.size = emitter.size
        temp_emitter.spread = emitter.spread
        temp_emitter.speed = emitter.speed
        temp_emitter.lifetime = emitter.lifetime

        temp_emitter.has_homing = emitter.options.contains(.homing)
        temp_emitter.has_borderbound = emitter.options.contains(.borderBound)
        temp_emitter.has_lifetime = emitter.options.contains(.lifetime)
        temp_emitter.has_intercollision = emitter.options.contains(.intercollision)
        temp_emitter.has_can_add_particles = emitter.options.contains(.canAddParticles)

        let id = emitters.count
        emitters.append(temp_emitter)

        // Increase the total amount of particles used
        particleCount += hasCanAddParticles ? 0 : emitter.count

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

    private func updateParticles(commandBuffer: MTLCommandBuffer) {
        
        if emitters.count == 0 { return }
    
        if !hasInit {

            initGPUBuffers(commandBuffer: commandBuffer)

            hasInit = true
        }
        
        if simParam.clearParticles { setGPUParticleCount(commandBuffer: commandBuffer, value: 0) }

        commandBuffer.pushDebugGroup("Particles Update")

        // Update emitters
        for idx in emitters.indices {
//            emitters[idx].size = gParticleSize
            emitters[idx].target_pos = attractPoint
//            emitters[idx].color = particleColor
            emitters[idx].has_intercollision = enableCollisions
            emitters[idx].gravity_force = enableGravity ? float2(0, gravityForce) : float2(0)
        }

        // Update emitter buffers
        emittersBuffer.contents().copyMemory(from: &emitters, byteCount: MemoryLayout<_Emitter>.stride * emitters.count)


        let computeEncoder = commandBuffer.makeComputeCommandEncoder()!

        computeEncoder.setComputePipelineState(computePipelineState!)

        computeEncoder.setBuffer(emittersBuffer, offset: 0, index: BufferIndex.bf_emitters_index.rawValue)
        computeEncoder.setBuffer(emitterIndicesBuffer, offset: 0, index: BufferIndex.bf_emitter_indices_index.rawValue)

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

        if usesSeedBuffer {
            computeEncoder.setBuffer(seedBuffer, offset: 0, index: BufferIndex.bf_seed_buffer_index.rawValue)
            computeEncoder.setBuffer(fieldNodesBuffer, offset: 0, index: BufferIndex.bf_field_nodes_index.rawValue)
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
        simParam.emitter_count = UInt32(emitters.count)
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

    public func eraseParticles() {
        self.particleCount = 0
        self.emitters.removeAll()
        self.simParam.clearParticles = true
    }

    public func addParticlesToEmitter(_ emitterID: Int, count: Int) {

        simParam.shouldAddParticle = true
        simParam.add_particles_count = UInt32(count)
        simParam.selected_emitter_id = UInt32(emitterID)

        particleCount += count
    }
    
    public func addParticleWith(position: float2, color: float4, radius: Float) {

        if self.particleCount == self.maxParticles { return }

        self.particleCount += 1

        self.simParam.shouldAddParticle = true
        self.simParam.newParticlePosition = position
        self.simParam.newParticleVelocity = hasInitialVelocity ? float2(-1, 1) : float2(0)
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
