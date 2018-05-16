//
//  ParticleSystemManager.swift
//  Athi
//
//  Created by Marcus Mathiassen on 15/05/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

import Metal
import MetalKit

enum ParticleSystemRenderOption {
    case bloom
}

struct ParticleSystemDescriptor {
    var maxParticlesAvailable = 0
    var renderOptions: [ParticleSystemRenderOption] = []
}

class ParticleSystemManager {
    weak var device: MTLDevice! = nil
    var particleSystems: [ParticleSystem] = []

    init(device: MTLDevice) {
        self.device = device
    }
    func update(commandBuffer: MTLCommandBuffer) {
        for ps in particleSystems {
            ps.update(commandBuffer: commandBuffer, computeDevice: .gpu)
        }
    }
    func draw(view: MTKView, commandBuffer: MTLCommandBuffer, frameDescriptor: FrameDescriptor) {
        for ps in particleSystems {
            ps.draw(view: view, frameDescriptor: frameDescriptor, commandBuffer: commandBuffer)
        }
    }
    func addParticleSystem(descriptor: ParticleSystemDescriptor) {
    }

    func addEmitterTo(psID: Int, emitterDesc: PSEmitterDescriptor) {
    }
}
