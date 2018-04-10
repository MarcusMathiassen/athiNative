//
//  Emitter.swift
//  Athi
//
//  Created by Marcus Mathiassen on 09/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

import Metal
import MetalKit

class Emitter
{
    var position = float2(0)
    var direction = float2(1)
    var color = float4(1)
    
    
    
    var frequency: Float = 1 / 60
    var timer: Timer?
    var count = 1000
    
    var speed: Float = 5
    var accuracy: Float = 1
    
    var particleSystem: ParticleSystem
    
    init(device: MTLDevice)
    {
        
        particleSystem = ParticleSystem(device: device)
        particleSystem.enableBorderCollision = true
        particleSystem.enableGravity = false
        particleSystem.gravityForce = -0.1
        particleSystem.hasInitialVelocity = false
        particleSystem.enableCollisions = false
        particleSystem.useQuadtree = false
        
        // Configure a timer to fetch the data.
        timer = Timer(fire: Date(), interval: TimeInterval(frequency),
                      repeats: true, block: { _ in

                        for _ in 0 ..< self.count/60 {
                            var p = Particle()
                            p.pos = self.position
                            p.radius = 1.5
                            p.vel = self.direction * self.speed + randFloat2(-1 * self.accuracy, 1 * self.accuracy)
                            self.particleSystem.addParticle(p, color: self.color)
                        }
        })
        
        // Add the timer to the current run loop.
        RunLoop.current.add(timer!, forMode: .defaultRunLoopMode)
    
    }
    
    func update()
    {
        
        if particleSystem.particles.count > count {
            self.particleSystem.removeFirst(self.count/10)
        }
        
        print(particleSystem.particles.count)
        
        //color = colorOverTime(getTime())
        particleSystem.update()
    }
    
    func draw(renderEncoder: MTLRenderCommandEncoder, vp: float4x4)
    {
        particleSystem.draw(renderEncoder: renderEncoder)
    }
}
