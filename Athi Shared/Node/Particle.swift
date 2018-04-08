//
//  Particle.swift
//  Athi
//
//  Created by Marcus Mathiassen on 04/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

import MetalKit
import simd

struct Particle {
    var pos: float2 = float2(0, 0)
    var vel: float2 = float2(0, 0)
    var acc: float2 = float2(0, 0)

    var mass: Float = 0
    var radius: Float = 0
    var torque: Float = 0

    mutating func update() {
        vel += acc
        pos += vel
        acc *= 0
    }
}

class ParticleSystem: Node {
    var particles: [Particle] = []

    var positionBuffer: MTLBuffer?
    var modelBuffer: MTLBuffer?

    var numVerticesPerParticle: Int = 36

    init(device: MTLDevice?) {
        var positions: [float2] = []
        for i in 0 ... numVerticesPerParticle - 1 {
            let cont = Float(i) * Float.pi * 2 / Float(numVerticesPerParticle)
            let x = cos(cont)
            let y = sin(cont)
            positions.append(float2(x, y))
        }

        let positionsDataSize = positions.count * MemoryLayout.stride(ofValue: positions[0])
        positionBuffer = device?.makeBuffer(bytes: positions, length: positionsDataSize, options: .cpuCacheModeWriteCombined)
    }

    override func render(commandEncoder: MTLCommandEncoder) {
        for child in children {
            child.render(commandEncoder: commandEncoder)
        }
    }

    func addParticle(_ particle: Particle) {
        particles.append(particle)
    }

    func updateParticles() {
        var modelMatrices: [float4x4] = []

        for p in particles {
            var transform = Transform()
            transform.pos = float3(p.pos.x, p.pos.y, 0)
            transform.scale *= p.radius

            modelMatrices.append(transform.getModel())
        }
    }

    func drawParticles(view _: MTKView) {
    }
}
