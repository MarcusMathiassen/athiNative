//
//  ParticleSystem_SoA.swift
//  Athi
//
//  Created by Marcus Mathiassen on 12/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

class ParticleSystemSoA {
    
    // Amount of particles
    public var particleCount: Int = 0
    
    // Particle Sim data
    private var position: [float2] = []
    private var velocity: [float2] = []
    
    // Particle GPU data
    struct ParticleGPUData {
        var position: float2
        var color: float4
        var size: Float
    }
    
    private func updateParticles() {
        
        
        particles.ad
        
        for i in 0 ..< particleCount {
            position[i] += velocity[i]
        }
    }
}
