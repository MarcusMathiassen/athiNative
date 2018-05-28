//
//  ParticleSystemV2.swift
//  Athi
//
//  Created by Marcus Mathiassen on 24/05/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

import Foundation

import simd

struct EmitterDescriptor {
    var spawnPosition = float2(0)
    var spawnDirection = float2(0)
    var spawnSpeed: Float = 0.0
    var spawnRate: Float = 0.0
    var spawnSpread: Float = 0.0

    var size: Float = 0.0
    var lifetime: Float = 0.0
    var color = float4(1)
}

protocol ParticleType {
    var id: Int { get set }

    var position: float2 { get set }
    var velocity: float2 { get set }
    var size: Float { get set }
    var color: half4 { get set }
    var lifetime: Float { get set }
}

// The internal structure of a particle only contains its index.
// All other data is computed properties
struct Particle: ParticleType, Collidable, CustomStringConvertible {
    var id: Int = 0
    var position: float2 {
        get { return ParticleSystemV2._positions[id] }
        set { ParticleSystemV2._positions[id] = newValue } }
    var velocity: float2 {
        get { return ParticleSystemV2._velocities[id] }
        set { ParticleSystemV2._velocities[id] = newValue } }
    var size: Float {
        get { return ParticleSystemV2._sizes[id] }
        set { ParticleSystemV2._sizes[id] = newValue } }

    /// The mass is based on the radius and with a fixed density of 1.0
    var mass: Float { return size * size * Float.pi }
    var color: half4 {
        get { return ParticleSystemV2._colors[id] }
        set { ParticleSystemV2._colors[id] = newValue } }
    var lifetime: Float {
        get { return ParticleSystemV2._lifetimes[id] }
        set { ParticleSystemV2._lifetimes[id] = newValue } }
    var description: String {
        return "id: \(id), position: \(position), velocity: \(velocity), size: \(size), color: \(color), lifetime: \(lifetime)"
    }
}

final class ParticleSystemV2 {

    var particleCount: Int = 0
    var maxParticleCount: Int = 10_000

    static var _positions: [float2] = []
    static var _velocities: [float2] = []
    static var _sizes: [Float] = []
    static var _colors: [half4] = []
    static var _lifetimes: [Float] = []

    var particles: [Particle] {
        get {
            var allParticles: [Particle] = []
            for emitter in emitters {
                allParticles.append(contentsOf: emitter.particles)
            }
            return allParticles
        }
        set {
            for index in newValue.indices {
                ParticleSystemV2._positions[index] = newValue[index].position
                ParticleSystemV2._velocities[index] = newValue[index].velocity
                ParticleSystemV2._sizes[index] = newValue[index].size
                ParticleSystemV2._colors[index] = newValue[index].color
                ParticleSystemV2._lifetimes[index] = newValue[index].lifetime
            }
        }
    }

    struct Emitter {
        var id: Int = 0

        var particles: [Particle] = []
        var particleCount = 0
        var maxParticleCount = 0

        var spawnPosition = float2(0)
        var spawnDirection = float2(0)
        var spawnSpeed: Float = 0.0

        var spawnSpread: Float = 0.0

        var spawnSize: Float = 0.0
        var spawnLifetime: Float = 0
        var spawnRate: Float = 0
        var spawnColor = half4(0)

        mutating func resetParticles(particleCount: Int) {
            for i in 0 ..< maxParticleCount {
                var p = Particle()
                p.id = i + particleCount
                p.position = spawnPosition
                p.velocity = (spawnDirection * spawnSpeed) + randFloat2(-spawnSpread, spawnSpread)
                p.size = spawnSize
                p.color = spawnColor
                p.lifetime = spawnLifetime * randFloat(0.5, 1.0)
                particles.append(p)
            }
        }

        mutating func update() {
            for index in particles.indices {

                var  pos = particles[index].position
                var  vel = particles[index].velocity

                var  color = particles[index].color
                var  size = particles[index].size
                var  lifetime = particles[index].lifetime

                if lifetime < 0 {
                    let newVel = spawnDirection * spawnSpeed

                    pos = spawnPosition
                    vel = newVel + randFloat2(-spawnSpread, spawnSpread)

                    // Update variables if available
                    size = spawnSize
                    color = spawnColor
                    lifetime = spawnLifetime * randFloat(0.5, 1.0)
                } else {
                    lifetime -= 1.0 / 60.0
                }

//                vel.y += -0.0981

                particles[index].velocity = vel
                particles[index].position = pos + vel
                particles[index].color = color
                particles[index].size = size
                particles[index].lifetime = lifetime

            }
        }
    }

    var positions: [float2]     { return ParticleSystemV2._positions }
    var velocities: [float2]    { return ParticleSystemV2._velocities }
    var sizes: [Float]          { return ParticleSystemV2._sizes }
    var colors: [half4]         { return ParticleSystemV2._colors }
    var lifetimes: [Float]      { return ParticleSystemV2._lifetimes }

    static let sharedInstance = ParticleSystemV2()
    private init() {
        increaseBuffers(by: maxParticleCount)
    }
    var emitters: [Emitter] = []

    func increaseBuffers(by count: Int) {

        ParticleSystemV2._positions.reserveCapacity(particleCount + count)
        ParticleSystemV2._velocities.reserveCapacity(particleCount + count)
        ParticleSystemV2._sizes.reserveCapacity(particleCount + count)
        ParticleSystemV2._colors.reserveCapacity(particleCount + count)
        ParticleSystemV2._lifetimes.reserveCapacity(particleCount + count)
        
        ParticleSystemV2._positions.append(contentsOf: [float2](repeating: float2(0), count: count))
        ParticleSystemV2._velocities.append(contentsOf: [float2](repeating: float2(0), count: count))
        ParticleSystemV2._sizes.append(contentsOf: [Float](repeating: Float(0), count: count))
        ParticleSystemV2._colors.append(contentsOf: [half4](repeating: half4(0), count: count))
        ParticleSystemV2._lifetimes.append(contentsOf: [Float](repeating: Float(0), count: count))
    }

    typealias EmitterHandle = Int
    func makeEmitter(descriptor: EmitterDescriptor) -> EmitterHandle {

        var emitter = Emitter()

        emitter.particleCount = 0
        emitter.maxParticleCount = Int(descriptor.spawnRate * descriptor.lifetime)

        emitter.id = emitters.count

        emitter.spawnPosition = descriptor.spawnPosition
        emitter.spawnDirection = descriptor.spawnDirection
        emitter.spawnSpeed = descriptor.spawnSpeed
        emitter.spawnRate = descriptor.spawnRate
        emitter.spawnSpread = descriptor.spawnSpread

        emitter.spawnSize = descriptor.size
        emitter.spawnColor = half4(descriptor.color)
        emitter.spawnLifetime = descriptor.lifetime

        if particleCount > maxParticleCount {
            maxParticleCount = particleCount
        }

        increaseBuffers(by: emitter.maxParticleCount)
        emitter.resetParticles(particleCount: particleCount)

        particleCount += emitter.maxParticleCount

        let emitterHandle = emitters.count
        emitters.append(emitter)

        return emitterHandle
    }

    func update() {
        for i in emitters.indices {
            emitters[i].update()
        }
    }
}

let particleSystemV2 = ParticleSystemV2.sharedInstance

import Metal
import MetalKit.MTKView

final class ParticleRenderer {

    var particleCount: Int = 0
    var allocatedParticleCount: Int = 0

    var pipelineState: MTLRenderPipelineState! = nil

    var positionsBuffer: MTLBuffer! = nil
    var sizesBuffer: MTLBuffer! = nil
    var colorsBuffer: MTLBuffer! = nil
    var lifetimesBuffer: MTLBuffer! = nil

    let device: MTLDevice

    func updateGPUBuffers() {

        // Check if we need to allocate more space on the buffers
        if allocatedParticleCount < particleCount {

            allocatedParticleCount = particleCount

            positionsBuffer = device.makeBuffer(length: MemoryLayout<float2>.stride * particleCount, options: .storageModeShared)
            sizesBuffer = device.makeBuffer(length: MemoryLayout<Float>.stride * particleCount, options: .storageModeShared)
            colorsBuffer = device.makeBuffer(length: MemoryLayout<half4>.stride * particleCount, options: .storageModeShared)
            lifetimesBuffer = device.makeBuffer(length: MemoryLayout<Float>.stride * particleCount, options: .storageModeShared)
        }

        positionsBuffer.contents().copyMemory(from: particleSystemV2.positions,
                                              byteCount: MemoryLayout<float2>.stride * particleCount)
        sizesBuffer.contents().copyMemory(from: particleSystemV2.sizes,
                                              byteCount: MemoryLayout<Float>.stride * particleCount)
        colorsBuffer.contents().copyMemory(from: particleSystemV2.colors,
                                              byteCount: MemoryLayout<half4>.stride * particleCount)
        lifetimesBuffer.contents().copyMemory(from: particleSystemV2.lifetimes,
                                              byteCount: MemoryLayout<Float>.stride * particleCount)
    }

    init() {
        self.device = MTLCreateSystemDefaultDevice()!

        let library = device.makeDefaultLibrary()!
        let vertFunc = library.makeFunction(name: "particleVert")!
        let fragFunc = library.makeFunction(name: "particleFrag")!

        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.label = "pipelineDesc"
        pipelineDesc.vertexFunction = vertFunc
        pipelineDesc.fragmentFunction = fragFunc
        pipelineDesc.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            try pipelineState = device.makeRenderPipelineState(descriptor: pipelineDesc)
        } catch {
            print("Error: \(error)")
        }
    }

    func drawParticles(view: MTKView, commandBuffer: MTLCommandBuffer) {

        particleCount = particleSystemV2.particleCount
        
        if particleCount == 0 { return }

        let renderPassDesc = view.currentRenderPassDescriptor
        if renderPassDesc != nil {
            let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc!)!

             renderEncoder.setRenderPipelineState(pipelineState!)

            // Update buffers
            updateGPUBuffers()

            // Upload buffers
            renderEncoder.setVertexBuffers(
                [positionsBuffer, sizesBuffer, colorsBuffer, lifetimesBuffer],
                offsets: [0,0,0,0],
                range: 0 ..< 4)

            renderEncoder.setVertexBytes(&viewportSize,
                                         length: MemoryLayout<float2>.stride,
                                         index: BufferIndex.bf_viewportSize_index.rawValue)

            renderEncoder.drawPrimitives(
                type: .point,
                vertexStart: 0,
                vertexCount: particleCount
            )

            renderEncoder.endEncoding()
        }
    }
}
