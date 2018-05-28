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
    case friendly = "fc_is_friendly"
}

enum RenderingOption {
    case circles
    case pixels
    case points
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
    case respawns
    case friendly
}

extension float2: Codable {
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let x = try values.decode(Float.self, forKey: .x)
        let y = try values.decode(Float.self, forKey: .y)
        self.init(x, y)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
    }

    private enum CodingKeys: String, CodingKey {
        case x, y
    }
}

extension float4: Codable {
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let x = try values.decode(Float.self, forKey: .x)
        let y = try values.decode(Float.self, forKey: .y)
        let z = try values.decode(Float.self, forKey: .z)
        let w = try values.decode(Float.self, forKey: .w)
        self.init(x, y, z, w)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
        try container.encode(z, forKey: .z)
        try container.encode(w, forKey: .w)
    }

    private enum CodingKeys: String, CodingKey {
        case x, y, z, w
    }
}

struct PSEmitterDescriptor {
    var isActive: Bool = false
    var spawnPoint: float2 = float2(0, 0)
    var spawnDirection: float2 = float2(0, 1)
    var spawnRate: Float = 10.0
    var attackDamage: Float = 1.0
    var particleSpeed: Float = 5.0
    var particleColor: float4 = float4(1)
    var particleSize: Float = 1.0
    var particleLifetime: Float = 1.0
    var mozzleSpread: Float = 1.0
    var options: [EmitterOptions] = [.lifetime, .respawns]
}

struct Emitter {
    var isActive: Bool = false
    var position: float2 = float2(0)
    var direction: float2 = float2(0)
    var size: Float32 = 0
    var speed: Float32 = 0
    var lifetime: Float32 = 0
    var spread: Float32 = 0
    var color: half4 = half4(0,0,0,0)

    var particleCount: Int32 = 0
    var maxParticleCount: Int32 = 0
    var startIndex: Int32 = 0
    var attackDamage: Float = 0.5

    var hasHoming: Bool = false
    var hasLifetime: Bool = false
    var hasBorderBound: Bool = false
    var hasIntercollision: Bool = false
    var hasCanAddParticles: Bool = false
    var hasRespawns: Bool = false
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

    var renderingOption: RenderingOption = .points

    var primitiveRenderer: PrimitiveRenderer

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

    private var pipelineState: MTLRenderPipelineState?
    private var computePipelineState: MTLComputePipelineState?
    private var mNoDepthTest: MTLDepthStencilState?

    var inTexture: MTLTexture! = nil
    var outTexture: MTLTexture! = nil
    var finalTexture: MTLTexture! = nil

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

        emitter.particleCount = Int32(descriptor.spawnRate * descriptor.particleLifetime);
        emitter.maxParticleCount = Int32(descriptor.spawnRate * descriptor.particleLifetime)

        emitter.attackDamage = descriptor.attackDamage
        emitter.lifetime = descriptor.particleLifetime
        emitter.position = descriptor.spawnPoint
        emitter.size = descriptor.particleSize
        emitter.color = half4(descriptor.particleColor)
        emitter.direction = descriptor.spawnDirection

        emitter.speed = descriptor.particleSpeed
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
        self.maxEmitterCount = maxParticles / 100

        self.options = options

        self.device = device
        quad = Quad(device: device)

        primitiveRenderer = PrimitiveRenderer(device: device)

        emitterIndices = [UInt16](repeating: 0, count: maxParticles)

        // Initalize our GPU buffers
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
            colorsBuffer = device.makeBuffer(length: MemoryLayout<half4>.stride * maxParticles,
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
        
        textureDesc.resourceOptions = .storageModePrivate

        textureDesc.usage = .shaderRead
        inTexture = device.makeTexture(descriptor: textureDesc)!

        textureDesc.usage = .shaderWrite
        outTexture = device.makeTexture(descriptor: textureDesc)!
        finalTexture = device.makeTexture(descriptor: textureDesc)!

        let library = device.makeDefaultLibrary()!
        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.label = "pipelineDesc"
        pipelineDesc.vertexFunction = library.makeFunction(name: "particle_vert")!
        pipelineDesc.fragmentFunction = library.makeFunction(name: "particle_frag")!
        pipelineDesc.colorAttachments[0].pixelFormat = Renderer.pixelFormat
        pipelineDesc.colorAttachments[1].pixelFormat = Renderer.pixelFormat

        do {
            try pipelineState = device.makeRenderPipelineState(descriptor: pipelineDesc)
        } catch let error {
            print("Error: \(error)")
        }

        let depthStencilDesc = MTLDepthStencilDescriptor()
        depthStencilDesc.isDepthWriteEnabled = false
        mNoDepthTest = device.makeDepthStencilState(descriptor: depthStencilDesc)!

        let constVals = MTLFunctionConstantValues()
//        // Set all values to false first
        var falseVal = false
        constVals.setConstantValue(&falseVal, type: .bool, withName: ParticleOption.attractedToMouse.rawValue)
        constVals.setConstantValue(&falseVal, type: .bool, withName: ParticleOption.borderBound.rawValue)
        constVals.setConstantValue(&falseVal, type: .bool, withName: ParticleOption.canAddParticles.rawValue)
        constVals.setConstantValue(&falseVal, type: .bool, withName: ParticleOption.drawToTexture.rawValue)
        constVals.setConstantValue(&falseVal, type: .bool, withName: ParticleOption.homing.rawValue)
        constVals.setConstantValue(&falseVal, type: .bool, withName: ParticleOption.intercollision.rawValue)
        constVals.setConstantValue(&falseVal, type: .bool, withName: ParticleOption.respawns.rawValue)
        constVals.setConstantValue(&falseVal, type: .bool, withName: ParticleOption.friendly.rawValue)

        // Then set all found in options to true
        var trueVal = true
        for option in options {
            constVals.setConstantValue(&trueVal, type: .bool, withName: option.rawValue)
        }

        print(constVals)


        var computeFunc: MTLFunction! = nil
        do {
            try computeFunc = library.makeFunction(name: "basic_update", constantValues: constVals)
            computeFunc.label = "basic_update"
        } catch let error {
            print("Error: \(error)")
        }
        do {
            try computePipelineState = device.makeComputePipelineState(function: computeFunc!)
        } catch let error {
            print("Error: \(error)")
        }

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

    public func draw(view: MTKView, frameDescriptor: FrameDescriptor, commandBuffer: MTLCommandBuffer) {

        if emitters.count == 0 { return }

        commandBuffer.pushDebugGroup("ParticleSystem Draw")

        let viewRenderPassDesc = view.currentRenderPassDescriptor
        if viewRenderPassDesc != nil {

            viewRenderPassDesc?.colorAttachments[0].loadAction = .clear
            viewRenderPassDesc?.colorAttachments[0].texture = inTexture
            viewRenderPassDesc?.colorAttachments[1].loadAction = .clear
            viewRenderPassDesc?.colorAttachments[1].texture = outTexture

            let blurKernel = MPSImageGaussianBlur(device: device, sigma: blurStrength)
            blurKernel.encode(commandBuffer: commandBuffer, sourceTexture: inTexture, destinationTexture: outTexture)
            quad.mix(commandBuffer: commandBuffer, inputTexture1: inTexture, inputTexture2: outTexture, outTexture: (view.currentDrawable?.texture)!, sigma: 5)

            let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: viewRenderPassDesc!)!

            renderEncoder.pushDebugGroup("Draw particles")

            renderEncoder.setRenderPipelineState(pipelineState!)
            renderEncoder.setDepthStencilState(mNoDepthTest)

            renderEncoder.setVertexBuffer(positionsBuffer, offset: 0, index: BufferIndex.bf_positions_index.rawValue)
            renderEncoder.setVertexBuffer(radiiBuffer, offset: 0, index: BufferIndex.bf_radii_index.rawValue)
            renderEncoder.setVertexBuffer(colorsBuffer, offset: 0, index: BufferIndex.bf_colors_index.rawValue)
            renderEncoder.setVertexBuffer(lifetimesBuffer,
                                          offset: 0,
                                          index: BufferIndex.bf_lifetimes_index.rawValue)
            renderEncoder.setVertexBytes(&viewportSize, length: MemoryLayout<float2>.stride,
                                         index: BufferIndex.bf_viewportSize_index.rawValue)

            renderEncoder.setTriangleFillMode(frameDescriptor.fillMode)
            renderEncoder.drawPrimitives(
                type: .point,
                vertexStart: 0,
                vertexCount: particleCount
            )

            renderEncoder.popDebugGroup()
            renderEncoder.endEncoding()

            commandBuffer.popDebugGroup()
        }

        for emitter in emitters {
            primitiveRenderer.drawRect(position: emitter.position, color: float4(1), size: emitter.size*0.5)
        }
        primitiveRenderer.draw(view: view, frameDescriptor: frameDescriptor, commandBuffer: commandBuffer)
    }

    private func update_particles(commandBuffer: MTLCommandBuffer) {

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

        for i in emitters.indices {
            emitters[i].position.x += Float(sin(getTime())) * 5
            emitters[i].position.y += Float(cos(getTime())) * 5
        }

        // Update emitter buffers
        emittersBuffer.contents().copyMemory(from: &emitters, byteCount: MemoryLayout<Emitter>.stride * emitters.count)

        let computeEncoder = commandBuffer.makeComputeCommandEncoder()!

        computeEncoder.setComputePipelineState(computePipelineState!)

        var globalParam = GlobalParam()
        globalParam.attractPoint = attractPoint
        globalParam.currentTime = Float(getTime())
        globalParam.deltaTime = 1/60
        globalParam.emitterCount = Int32(emitters.count)
        globalParam.mousePos = mousePos
        globalParam.gravityForce = enableGravity ? float2(0, gravityForce) : float2(0)
        globalParam.particleCount = Int32(particleCount)
        globalParam.viewportSize = viewportSize
        globalParam.seed = Int32(randFloat(0, 100))

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
        let threadExecutionWidth = (computePipelineState?.threadExecutionWidth)!

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

        for emitter in emitters {
            primitiveRenderer.drawHollowRect(position: emitter.position, color: color, size: emitter.size*0.5)
        }
    }

    public func update(commandBuffer: MTLCommandBuffer,
                       computeDevice: ComputeDeviceOption) {

        if isPaused { return }

        update_particles(commandBuffer: commandBuffer)
    }

    public func eraseParticles() {
        self.particleCount = 0
        self.clearParticles = true
        self.emitters.removeAll()
    }

    private func updateEmitterIndices(commandBuffer: MTLCommandBuffer) {

        for emitterIndex in emitters.indices {
            let counter = emitters[emitterIndex].startIndex
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
//        if shouldAddEmitter { return -1 }
        if emitters.count+1 > maxEmitterCount ||
            Int(emitter.particleCount) + particleCount > maxParticles { return -1; }

        emitter.startIndex = Int32(particleCount)

        let id = emitters.count
        emitters.append(emitter)

        // Increase the total amount of particles used
        particleCount += Int(emitter.particleCount)

        shouldAddEmitter = true
        emittersToAddCount += 1

        return id
    }

}
