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

        var particleCount = 0
        var particleIndices: CountableRange<Int> { return startIndex ..< startIndex + particleCount }

        var spawnPosition = float2(0, 0)
        var spawnDirection = float2(0, 0)
        var spawnSpeed: Float = 0.0
        var spawnSpread: Float = 0.0
        var spawnSize: Float = 0.0
        var spawnLifetime: Float = 0
        var spawnRate: Float = 0
        var spawnColor = float4(0,0,0,0)

        init(_ descriptor: EmitterDescriptor) {
            particleCount = Int(descriptor.spawnRate * descriptor.lifetime)
            spawnPosition = descriptor.spawnPosition
            spawnDirection = descriptor.spawnDirection
            spawnSpeed = descriptor.spawnSpeed
            spawnRate = descriptor.spawnRate
            spawnSpread = descriptor.spawnSpread

            spawnSize = descriptor.size
            spawnColor = float4(descriptor.color)
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
    var colors: [float4] = []
    var lifetimes: [Float] = []

    struct Particle {
        var position = float2(0, 0)
        var velocity = float2(0, 0)
        var size = Float(0)
        var color = float4(0,0,0,0)
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
        positions.removeAll(keepingCapacity: true)
        colors.removeAll(keepingCapacity: true)
        sizes.removeAll(keepingCapacity: true)
        lifetimes.removeAll(keepingCapacity: true)
        particleCount = 0
        maxParticleCount = 0
    }
    
    func increaseBuffers(by count: Int) {

        if maxParticleCount >= particleCount + count {
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
        colors.append(contentsOf: [float4](repeating: float4(0,0,0,0), count: count))
        lifetimes.append(contentsOf: [Float](repeating: Float(-1), count: count))
        
        maxParticleCount = particleCount
    }

    func makeEmitter(descriptor: EmitterDescriptor) -> Int {

        var emitter = Emitter(descriptor)

        emitter.id = emitters.count
        emitter.startIndex = particleCount
        
        increaseBuffers(by: emitter.particleCount)
        particleCount += emitter.particleCount
        
        let emitterHandle = emitters.count
        emitters.append(emitter)
        emitterDescriptions.append(descriptor)

        return emitterHandle
    }
    
    func getParticleByIndex(_ index: Int) -> Particle {
        assert(index <= particleCount)
        let  pos = positions[index]
        let  vel = velocities[index]
        let  color = colors[index]
        let  size = sizes[index]
        let  lifetime = lifetimes[index]
        return Particle(position: pos, velocity: vel, size: size, color: color, lifetime: lifetime)
    }

    func update() {
        for emitter in emitters {
            for index in emitter.particleIndices {
                
                var p = getParticleByIndex(index)
                
                if p.lifetime < 0 {
                    let newVel = emitter.spawnDirection * emitter.spawnSpeed

                    p.position = emitter.spawnPosition
                    p.velocity = newVel + randFloat2(-emitter.spawnSpread, emitter.spawnSpread)

                    // Update variables if available
                    p.size = emitter.spawnSize
                    p.color = emitter.spawnColor
                    p.lifetime = emitter.spawnLifetime * randFloat(0.5, 1.0)
                } else {
                    p.lifetime -= 1.0 / 60.0
                }

//                p.velocity.y += -0.0981
                
                p.color.w = p.lifetime

                velocities[index] = p.velocity
                positions[index] = p.position + p.velocity
                colors[index] = p.color
                sizes[index] = p.size
                lifetimes[index] = p.lifetime
            }
        }
    }
}
