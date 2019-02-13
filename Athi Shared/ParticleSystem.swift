//
//  ParticleSystemV2.swift
//  Athi
//
//  Created by Marcus Mathiassen on 24/05/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

import Foundation

import simd

struct EmitterDescriptor: Codable {
    var spawnPosX: Float = 0
    var spawnPosY: Float = 0
    var spawnDirX: Float = 0
    var spawnDirY: Float = 0
    var spawnSpeed: Float = 0
    var spawnRate: Float = 0
    var spawnSpread: Float = 0

    var size: Float = 0.0
    var lifetime: Float = 0.0
    var r: Float = 0
    var g: Float = 0
    var b: Float = 0
    var a: Float = 0

    var spawnPosition: float2 {
        get { return float2(spawnPosX, spawnPosY) }
        set { spawnPosX = newValue.x; spawnPosY = newValue.y }
    }
    var spawnDirection: float2 {
        get { return float2(spawnDirX, spawnDirY) }
        set { spawnDirX = newValue.x; spawnDirY = newValue.y }
    }
    var color: float4 {
        get { return float4(r, g, b, a) }
        set { r = newValue.x; g = newValue.y; b = newValue.z; a = newValue.w }
    }
}

final class ParticleSystem {

    struct Emitter {

        var id: Int = 0
        var startIndex: Int = 0
        var particleIndices: CountableRange<Int> { return startIndex ..< startIndex + maxParticleCount }

        var particleCount = 0
        var maxParticleCount = 0

        var spawnPosition = float2(0, 0)
        var spawnDirection = float2(0, 0)
        var spawnSpeed: Float = 0.0
        var spawnSpread: Float = 0.0
        var spawnSize: Float = 0.0
        var spawnLifetime: Float = 0
        var spawnRate: Float = 0
        var spawnColor = half4(0)

        init(_ descriptor: EmitterDescriptor) {
            particleCount = 0
            maxParticleCount = Int(descriptor.spawnRate * descriptor.lifetime)
            spawnPosition = descriptor.spawnPosition
            spawnDirection = descriptor.spawnDirection
            spawnSpeed = descriptor.spawnSpeed
            spawnRate = descriptor.spawnRate
            spawnSpread = descriptor.spawnSpread

            spawnSize = descriptor.size
            spawnColor = half4(descriptor.color)
            spawnLifetime = descriptor.lifetime
        }
    }

    var emitterDescriptions: [EmitterDescriptor] = []
    var emitters: [Emitter] = []

    var particleCount: Int = 0
    var maxParticleCount: Int = 0

    // Particle data
    var positions: [float2] = []
    var velocities: [float2] = []
    var sizes: [Float] = []
    var colors: [half4] = []
    var lifetimes: [Float] = []

    struct Particle {
        var position = float2(0, 0)
        var velocity = float2(0, 0)
        var size = Float(0)
        var color = half4(0)
        var lifetime = Float(0)
    }

    init() {
    }

    func save() {
        if let encodedData = try? JSONEncoder().encode(emitterDescriptions) {
            let path = "emitters.json"
            do {
                try encodedData.write(to: URL(fileURLWithPath: path))
            }
            catch {
                print("Failed to write JSON data: \(error.localizedDescription)")
            }
        }
    }

    func load() {
        do {
            let path = "emitters.json"
            let data = try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
            do {
                let decodedData = try JSONDecoder().decode([EmitterDescriptor].self, from: data)
                clearEmitters()
                emitterDescriptions.removeAll()
                emitters.reserveCapacity(decodedData.count)
                emitterDescriptions.reserveCapacity(decodedData.count)
                for emitterDesc in decodedData {
                    _ = makeEmitter(descriptor: emitterDesc)
                }
            } catch {
                print("Error reading file \(path): \(error.localizedDescription)")
            }
        } catch {
            print("Failed to read JSON data: \(error.localizedDescription)")
        }
    }

    func clearEmitters() {
        emitters.removeAll(keepingCapacity: true)
        particleCount = 0
        maxParticleCount = 0
    }

    func increaseBuffers(by count: Int) {

        if positions.capacity >= particleCount + count {
            return
        }

        positions.reserveCapacity(particleCount + count)
        velocities.reserveCapacity(particleCount + count)
        sizes.reserveCapacity(particleCount + count)
        colors.reserveCapacity(particleCount + count)
        lifetimes.reserveCapacity(particleCount + count)

        positions.append(contentsOf: [float2](repeating: float2(0, 0), count: count))
        velocities.append(contentsOf: [float2](repeating: float2(0, 0), count: count))
        sizes.append(contentsOf: [Float](repeating: Float(0), count: count))
        colors.append(contentsOf: [half4](repeating: half4(0), count: count))
        lifetimes.append(contentsOf: [Float](repeating: Float(-1), count: count))
    }

    func makeEmitter(descriptor: EmitterDescriptor) -> Int {

        var emitter = Emitter(descriptor)

        emitter.id = emitters.count
        emitter.startIndex = particleCount
        
        increaseBuffers(by: emitter.maxParticleCount)
        
        let emitterHandle = emitters.count
        emitters.append(emitter)
        emitterDescriptions.append(descriptor)

        return emitterHandle
    }

    func update() {
        for emitter in emitters {
            for index in emitter.particleIndices {
                
                var  pos = positions[index]
                var  vel = velocities[index]

                var  color = colors[index]
                var  size = sizes[index]
                var  lifetime = lifetimes[index]

                if lifetime < 0 {
                    let newVel = emitter.spawnDirection * emitter.spawnSpeed

                    pos = emitter.spawnPosition
                    vel = newVel + randFloat2(-emitter.spawnSpread, emitter.spawnSpread)

                    // Update variables if available
                    size = emitter.spawnSize
                    color = emitter.spawnColor
                    lifetime = emitter.spawnLifetime * randFloat(0.5, 1.0)
                } else {
                    lifetime -= 1.0 / 60.0
                }

                vel.y += -0.0981
                
                color.w = toHalf(lifetime)

                velocities[index] = vel
                positions[index] = pos + vel
                colors[index] = color
                sizes[index] = size
                lifetimes[index] = lifetime
            }
        }
    }
}

import Metal
import MetalKit
import MetalPerformanceShaders

final class ParticleRenderer {

    var fullscreenEffect: Quad

    var particleCount: Int = 0
    var allocatedParticleCount: Int = 0

    var pipelineState: MTLRenderPipelineState! = nil

    var textureLoader: MTKTextureLoader! = nil
    var particleTexture: MTLTexture! = nil

    var inTexture: MTLTexture! = nil
    var outTexture: MTLTexture! = nil

    var indexBuffer: MTLBuffer

    var positions: [float2] = []
    var sizes: [Float] = []
    var colors: [half4] = []

    var positionsBuffer: MTLBuffer! = nil
    var sizesBuffer: MTLBuffer! = nil
    var colorsBuffer: MTLBuffer! = nil

    let device: MTLDevice

    init() {
        self.device = MTLCreateSystemDefaultDevice()!

        fullscreenEffect = Quad(device: device)

        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.resourceOptions = .storageModePrivate
        textureDescriptor.width = Int(framebufferWidth)
        textureDescriptor.height = Int(framebufferHeight)
        textureDescriptor.depth = 1
        textureDescriptor.pixelFormat = .bgra8Unorm
        textureDescriptor.storageMode = .private
        textureDescriptor.sampleCount = 1
        textureDescriptor.textureType = .type2D
        textureDescriptor.usage = [.shaderRead, .renderTarget]

        inTexture = device.makeTexture(descriptor: textureDescriptor)

        textureDescriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        outTexture = device.makeTexture(descriptor: textureDescriptor)

        let indices: [UInt16] = [0, 1, 2, 0, 2, 3]
        indexBuffer = device.makeBuffer(
            bytes: indices,
            length: MemoryLayout<UInt16>.stride * 6,
            options: .storageModeShared)!

        textureLoader = MTKTextureLoader(device: device)

        do {
            try particleTexture = textureLoader.newTexture(name: "particleTexture", scaleFactor: 1.0, bundle: Bundle.main)
        } catch {
            print("Error: \(error)")
        }

        let library = device.makeDefaultLibrary()!
        let vertFunc = library.makeFunction(name: "particleVert")!
        let fragFunc = library.makeFunction(name: "particleFrag")!

        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.label = "pipelineDesc"
        pipelineDesc.vertexFunction = vertFunc
        pipelineDesc.fragmentFunction = fragFunc
        pipelineDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDesc.colorAttachments[0].isBlendingEnabled = true
        pipelineDesc.colorAttachments[0].rgbBlendOperation = .add
        pipelineDesc.colorAttachments[0].alphaBlendOperation = .add
        pipelineDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDesc.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        pipelineDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        pipelineDesc.colorAttachments[1].pixelFormat = .bgra8Unorm
        pipelineDesc.colorAttachments[1].isBlendingEnabled = true
        pipelineDesc.colorAttachments[1].rgbBlendOperation = .add
        pipelineDesc.colorAttachments[1].alphaBlendOperation = .add
        pipelineDesc.colorAttachments[1].sourceRGBBlendFactor = .sourceAlpha
        pipelineDesc.colorAttachments[1].sourceAlphaBlendFactor = .sourceAlpha
        pipelineDesc.colorAttachments[1].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDesc.colorAttachments[1].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            try pipelineState = device.makeRenderPipelineState(descriptor: pipelineDesc)
        } catch {
            print("Error: \(error)")
        }
    }

    func resizeTextures(newWidth: Int, newHeight: Int) {
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.resourceOptions = .storageModePrivate
        textureDescriptor.width = newWidth
        textureDescriptor.height = newHeight
        textureDescriptor.depth = 1
        textureDescriptor.pixelFormat = .bgra8Unorm
        textureDescriptor.storageMode = .private
        textureDescriptor.sampleCount = 1
        textureDescriptor.textureType = .type2D
        textureDescriptor.usage = [.shaderRead, .renderTarget]

        inTexture = device.makeTexture(descriptor: textureDescriptor)

        textureDescriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        outTexture = device.makeTexture(descriptor: textureDescriptor)

    }

    func updateGPUBuffers() {

        // Check if we need to allocate more space on the buffers
        if allocatedParticleCount < particleCount {

            allocatedParticleCount = particleCount

            positionsBuffer = device.makeBuffer(length: MemoryLayout<float2>.stride * particleCount, options: .storageModeShared)
            sizesBuffer = device.makeBuffer(length: MemoryLayout<Float>.stride * particleCount, options: .storageModeShared)
            colorsBuffer = device.makeBuffer(length: MemoryLayout<half4>.stride * particleCount, options: .storageModeShared)
        }

        positionsBuffer.contents().copyMemory(from: positions, byteCount: MemoryLayout<float2>.stride * particleCount)
        sizesBuffer.contents().copyMemory(from: sizes, byteCount: MemoryLayout<Float>.stride * particleCount)
        colorsBuffer.contents().copyMemory(from: colors, byteCount: MemoryLayout<half4>.stride * particleCount)
    }

    func drawParticles(view: MTKView, commandBuffer: MTLCommandBuffer, frameDescriptor: FrameDescriptor) {

        if particleCount == 0 { return }

        let renderPassDesc = MTLRenderPassDescriptor()
        renderPassDesc.colorAttachments[0].texture = inTexture
        renderPassDesc.colorAttachments[1].texture = outTexture
        renderPassDesc.colorAttachments[0].loadAction = .clear
        renderPassDesc.colorAttachments[1].loadAction = .clear
        renderPassDesc.colorAttachments[0].clearColor = frameDescriptor.clearColor
        renderPassDesc.colorAttachments[1].clearColor = frameDescriptor.clearColor

        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc)!

        renderEncoder.setRenderPipelineState(pipelineState!)
        renderEncoder.setTriangleFillMode(frameDescriptor.fillMode)

        // Update buffers
        updateGPUBuffers()

        // Upload buffers
        renderEncoder.setVertexBuffers(
            [positionsBuffer, sizesBuffer, colorsBuffer],
            offsets: [0, 0, 0, 0],
            range: 0 ..< 3)

        renderEncoder.setFragmentTexture(particleTexture, index: 0)

        renderEncoder.setVertexBytes(&viewportSize,
                                     length: MemoryLayout<float2>.stride,
                                     index: BufferIndex.bf_viewportSize_index.rawValue)

        renderEncoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: 6,
            indexType: .uint16,
            indexBuffer: indexBuffer,
            indexBufferOffset: 0,
            instanceCount: particleCount
        )

        renderEncoder.endEncoding()

        // Blur
        let blurKernel = MPSImageGaussianBlur(device: device, sigma: gBlurStrength)
        blurKernel.encode(commandBuffer: commandBuffer, sourceTexture: inTexture, destinationTexture: outTexture)

        fullscreenEffect.mix(commandBuffer: commandBuffer,
                             inputTexture1: inTexture,
                             inputTexture2: outTexture,
                             outTexture: (view.currentDrawable?.texture)!,
                             sigma: 5.0)
    }
}

func previewEmitter(emitterDescriptor: EmitterDescriptor) {
}
