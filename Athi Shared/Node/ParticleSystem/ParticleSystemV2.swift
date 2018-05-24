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

class ParticleSystemV2 {

    var particleCount: Int = 0
    var maxParticleCount: Int = 10_000

    static var _positions:      [float2]    = []
    static var _velocities:     [float2]    = []
    static var _radii:          [Float]     = []
    static var _masses:         [Float]     = []
    static var _colors:         [float4]    = []
    static var _lifetimes:      [Float]     = []

    class Emitter {
        var id: Int = 0
        var particleCount = 0
        var maxParticleCount = 0

        var spawnPosition = float2(0)
        var spawnDirection = float2(0)
        var spawnSpeed: Float = 0.0

        var spawnSpread: Float = 0.0

        var spawnSize: Float = 0.0
        var spawnLifetime: Float = 0
        var spawnRate: Float = 0
        var spawnColor = float4(1)

        struct Particle: CustomStringConvertible {
            var id: Int = 0
            var position: float2    { get { return ParticleSystemV2._positions[id] }      set { ParticleSystemV2._positions[id] = newValue } }
            var velocity: float2    { get { return ParticleSystemV2._velocities[id] }     set { ParticleSystemV2._velocities[id] = newValue } }
            var radius: Float       { get { return ParticleSystemV2._radii[id] }          set { ParticleSystemV2._radii[id] = newValue } }
            var mass: Float         { get { return ParticleSystemV2._masses[id] }         set { ParticleSystemV2._masses[id] = newValue } }
            var color: float4       { get { return ParticleSystemV2._colors[id] }         set { ParticleSystemV2._colors[id] = newValue } }
            var lifetime: Float     { get { return ParticleSystemV2._lifetimes[id] }      set { ParticleSystemV2._lifetimes[id] = newValue } }
            var description: String {
                return "id: \(id), position: \(position), velocity: \(velocity), radius: \(radius), mass: \(mass), color: \(color), lifetime: \(lifetime)"
            }
        }

        func resetParticles(particleCount: Int) {
            for i in 0 ..< maxParticleCount {
                var p = Particle()
                p.id = particleCount + i
                p.position = spawnPosition
                p.velocity = spawnDirection * spawnSpeed
                p.radius = spawnSize
                p.color = spawnColor
                p.lifetime = spawnLifetime
                particles.append(p)
            }
        }

        var particles: [Particle] = []

        func update() {
            for index in particles.indices {

                var  pos = particles[index].position
                var  vel = particles[index].velocity

                var  color = particles[index].color
                var  radius = particles[index].radius

                var  mass = particles[index].mass
                var  lifetime = particles[index].lifetime

                if lifetime < 0 {
                    let newVel = spawnDirection * spawnSpeed

                    pos = spawnPosition
                    vel = newVel + randFloat2(-spawnSpread, spawnSpread)

                    // Update variables if available
                    radius = spawnSize
                    color = spawnColor

                    lifetime = spawnLifetime * randFloat(0.5, 1.0)
                    mass = Float.pi * spawnSize * spawnSize

                } else {
                    lifetime -= 1.0 / 60.0
                }

                vel.y += -0.0981

                particles[index].velocity = vel
                particles[index].position = pos + vel
                particles[index].color = color
                particles[index].radius = radius
                particles[index].mass = mass
                particles[index].lifetime = lifetime

            }
        }
    }

    var positions: [float2]     { return ParticleSystemV2._positions }
    var velocities: [float2]    { return ParticleSystemV2._velocities }
    var radii: [Float]          { return ParticleSystemV2._radii }
    var masses: [Float]         { return ParticleSystemV2._masses }
    var colors: [float4]        { return ParticleSystemV2._colors }
    var lifetimes: [Float]      { return ParticleSystemV2._lifetimes }

    static let sharedInstance = ParticleSystemV2()
    private init() {
        increaseBuffers(by: maxParticleCount)
    }
    var emitters: [Emitter] = []

    func increaseBuffers(by count: Int) {

        ParticleSystemV2._positions.reserveCapacity(particleCount + count)
        ParticleSystemV2._velocities.reserveCapacity(particleCount + count)
        ParticleSystemV2._radii.reserveCapacity(particleCount + count)
        ParticleSystemV2._masses.reserveCapacity(particleCount + count)
        ParticleSystemV2._colors.reserveCapacity(particleCount + count)
        ParticleSystemV2._lifetimes.reserveCapacity(particleCount + count)

        for _ in 0 ..< count {
            ParticleSystemV2._positions.append(float2(0))
            ParticleSystemV2._velocities.append(float2(0))
            ParticleSystemV2._radii.append(Float(0))
            ParticleSystemV2._masses.append(Float(0))
            ParticleSystemV2._colors.append(float4(0))
            ParticleSystemV2._lifetimes.append(Float(0))
        }
    }

    func makeEmitter(descriptor: EmitterDescriptor) -> Emitter {

        let emitter = Emitter()

        emitter.particleCount = 0
        emitter.maxParticleCount = Int(descriptor.spawnRate * descriptor.lifetime)

        emitter.id = emitters.count

        emitter.spawnPosition = descriptor.spawnPosition
        emitter.spawnDirection = descriptor.spawnDirection
        emitter.spawnSpeed = descriptor.spawnSpeed
        emitter.spawnRate = descriptor.spawnRate
        emitter.spawnSpread = descriptor.spawnSpread

        emitter.spawnSize = descriptor.size
        emitter.spawnColor = descriptor.color
        emitter.spawnLifetime = descriptor.lifetime

        emitter.resetParticles(particleCount: particleCount)
        particleCount += emitter.maxParticleCount

        emitters.append(emitter)
        if particleCount > maxParticleCount {
            maxParticleCount = particleCount
        }
        increaseBuffers(by: emitter.maxParticleCount)

        return emitter
    }

    func update() {
        for i in emitters.indices {
            emitters[i].update()
        }
    }
}

let particleSystemV2 = ParticleSystemV2.sharedInstance

import Metal
import MetalKit

class ParticleRenderer {

    var particleCount: Int = 0

    var pipelineState: MTLRenderPipelineState! = nil

    var positionsBuffer: MTLBuffer! = nil
    var radiiBuffer: MTLBuffer! = nil
    var colorsBuffer: MTLBuffer! = nil
    var lifetimesBuffer: MTLBuffer! = nil

    let device: MTLDevice

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
        } catch let error {
            print("Error: \(error)")
        }
    }

    func drawParticles(view: MTKView, commandBuffer: MTLCommandBuffer) {

        particleCount = particleSystemV2.particleCount
        
        if particleCount == 0 {
            return
        }

        let renderPassDesc = view.currentRenderPassDescriptor
        if renderPassDesc != nil {
            let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc!)!

             renderEncoder.setRenderPipelineState(pipelineState!)
            
            // Update buffers
            positionsBuffer = device.makeBuffer(
                bytes: particleSystemV2.positions,
                length: MemoryLayout<float2>.stride * particleCount,
                options: .storageModeShared
            )

            radiiBuffer = device.makeBuffer(
                bytes: particleSystemV2.radii,
                length: MemoryLayout<Float>.stride * particleCount,
                options: .storageModeShared
            )

            colorsBuffer = device.makeBuffer(
                bytes: particleSystemV2.colors,
                length: MemoryLayout<float4>.stride * particleCount,
                options: .storageModeShared
            )

            lifetimesBuffer = device.makeBuffer(
                bytes: particleSystemV2.lifetimes,
                length: MemoryLayout<Float>.stride * particleCount,
                options: .storageModeShared
            )

            // Upload buffers
            renderEncoder.setVertexBuffers(
                [positionsBuffer, radiiBuffer, colorsBuffer, lifetimesBuffer],
                offsets: [0, 0, 0, 0],
                range: 0 ..< 4
            )

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
