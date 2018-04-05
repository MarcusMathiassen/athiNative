//
//  ParticleSystem.swift
//  Athi
//
//  Created by Marcus Mathiassen on 04/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

import simd
import MetalKit

struct Particle {
    var pos = float2(0)
    var vel = float2(0)
    var acc = float2(0)
    var radius: Float = 1
    var mass: Float = 0
    
    var rotation: Float = 0
    var torque: Float = 0
    
    mutating func update() {

        // Update pos/vel/acc
        vel.x += acc.x
        vel.y += acc.y
        pos.x += vel.x
        pos.y += vel.y
        acc *= 0

        torque *= 0.999
        rotation += torque
    }
}

class ParticleSystem: Entity {
    
    // Options
    var borderCollision: Bool = true
    var collisionEnergyLoss: Float = 0.98
    var gravityForce: Float = -0.981
    var enableGravity: Bool = false
    var enableCollisions: Bool = false
    var useAccelerometerAsGravity: Bool = false
    var hasInitialVelocity: Bool = true
    
    
    var particles: [Particle] = []
    
    var numVerticesPerParticle = 120
    
    var positions: [float2] = []
    var colors: [float4] = []
    var models: [float4x4] = []
    
    var positionBuffer: MTLBuffer?
    var colorBuffer: MTLBuffer?
    var modelBuffer: MTLBuffer?

    weak var device: MTLDevice?
    var pipelineState: MTLRenderPipelineState?
    
    init(device: MTLDevice?) {
        
        // Setup the particle vertices
        var k: Float = 0
        var lastVert = float2(0)
        for i in 0 ..< numVerticesPerParticle+3 {
           switch k
           {
           case 0:
               k += 1
               positions.append(lastVert)
           case 1:
               k += 1
               let cont =  Float(i) * Float.pi * 2 / Float(numVerticesPerParticle)
               let x = cos(cont)
               let y = sin(cont)
               lastVert = float2(x, y)
               positions.append(lastVert)
           case 2:
               k += 1
               k = 0
               positions.append(float2(0,0))
           default:
               k = 0
           }
       }

        positionBuffer = device?.makeBuffer(bytes: positions, length: MemoryLayout<float2>.stride * positions.count, options: .cpuCacheModeWriteCombined)
        
        self.device = device
        
        let library = device?.makeDefaultLibrary()!
        let vertexFunc = library?.makeFunction(name: "particleVert")
        let fragFunc = library?.makeFunction(name: "particleFrag")
        
        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.label = "ParticleSystem Pipeline"
        pipelineDesc.vertexFunction = vertexFunc
        pipelineDesc.fragmentFunction = fragFunc
        pipelineDesc.sampleCount = 2
        pipelineDesc.colorAttachments[0].pixelFormat = MTLPixelFormat.bgra8Unorm_srgb
        
        do {
            try pipelineState = device?.makeRenderPipelineState(descriptor: pipelineDesc)
        }
        catch {
            print("ParticleSystem Pipeline: Creating pipeline state failed")
        }
    }
    
    func eraseParticles() {
        particles.removeAll()
        models.removeAll()
        colors.removeAll()
    }
    
    func addParticle(position: float2, color: float4, radius: Float) {
        
        var p = Particle()
        p.pos = position
        if hasInitialVelocity { p.vel = randFloat2(-5,5) }
        p.radius = radius
        p.mass = Float.pi * radius * radius

        
        // Add new particle
        particles.append(p)
        
        // Add new color
        colors.append(color)
        
        // Add new transform
        models.append(float4x4())
    }
    
    func updateCollisions() {
        for i in 0 ..< particles.count {
            for j in 1 + i ..< particles.count {
                if collisionCheck(&particles[i], &particles[j]) {
                    collisionResolve(&particles[i], &particles[j])
                }
            }
        }
    }

    override func update() {
        
        if enableCollisions { updateCollisions() }

    }
    
    func updateBuffers() {
        colorBuffer = device?.makeBuffer(bytes: colors, length: MemoryLayout<float4>.size * particles.count, options: .cpuCacheModeWriteCombined)
        modelBuffer = device?.makeBuffer(bytes: models, length: MemoryLayout<float4x4>.size * particles.count, options: .cpuCacheModeWriteCombined)
    }
    
    override func draw(renderEncoder: MTLRenderCommandEncoder?, vp: float4x4) {
        if particles.count == 0 {
            return
        }
        
        updateBuffers()

        print("positoins:",particles.count)

        renderEncoder?.label = "ParticleSystem"
        renderEncoder?.setRenderPipelineState(pipelineState!)
        renderEncoder?.setTriangleFillMode(.fill)
        
        // Update particles
        
        var tempGravityForce = float2(0)
        if enableGravity {
            
            if useAccelerometerAsGravity {
                tempGravityForce = float2(accelerometer.x, accelerometer.y)
            } else {
                tempGravityForce.y = gravityForce
            }
        }
        
        for i in 0 ..< particles.count {
            
            particles[i].acc = tempGravityForce
            
            // Border collision
            if (particles[i].pos.x < 0 + particles[i].radius) {
                particles[i].pos.x = 0 + particles[i].radius
                particles[i].vel.x = -particles[i].vel.x * collisionEnergyLoss
            }
            if (particles[i].pos.x > framebufferWidth - particles[i].radius) {
                particles[i].pos.x = framebufferWidth - particles[i].radius
                particles[i].vel.x = -particles[i].vel.x * collisionEnergyLoss
            }
            if (particles[i].pos.y < 0 + particles[i].radius) {
                particles[i].pos.y = 0 + particles[i].radius
                particles[i].vel.y = -particles[i].vel.y * collisionEnergyLoss
            }
            if (particles[i].pos.y > framebufferHeight - particles[i].radius) {
                particles[i].pos.y = framebufferHeight - particles[i].radius
                particles[i].vel.y = -particles[i].vel.y * collisionEnergyLoss
            }
            
            particles[i].update()
            
            let p = particles[i]
            
            // Update models
            var transform = Transform()
            transform.pos = float3(p.pos.x, p.pos.y, 0)
            transform.scale = float3(p.radius, p.radius, 0)
            transform.rot.z = p.rotation
            let model = vp * transform.getModel()
            models[i] = model
        }
        
        renderEncoder?.setVertexBuffer(positionBuffer, offset: 0, index: 0)
        renderEncoder?.setVertexBuffer(colorBuffer, offset: 0, index: 1)
        renderEncoder?.setVertexBuffer(modelBuffer, offset: 0, index: 2)
        
        renderEncoder?.drawPrimitives(
            type: .triangle,
            vertexStart: 0,
            vertexCount: positions.count,
            instanceCount: particles.count
        )
    }



    func collisionCheck(_ a: inout Particle, _ b: inout Particle) -> Bool  {

      // Local variables
      let ax = a.pos.x;
      let ay = a.pos.y;
      let bx = b.pos.x;
      let by = b.pos.y;
      let ar = a.radius;
      let br = b.radius;

      // square collision check
      if (ax - ar < bx + br &&
          ax + ar > bx - br &&
          ay - ar < by + br &&
          ay + ar > by - br) {

        let dx = bx - ax;
        let dy = by - ay;

        let sum_radius = ar + br;
        let sqr_radius = sum_radius * sum_radius;

        let distance_sqrd = (dx * dx) + (dy * dy);

        // circle collision check
        return distance_sqrd < sqr_radius;
      }
      return false;
    }


    // Collisions response between two circles with varying radius and mass.
    func collisionResolve(_ a: inout Particle, _ b: inout Particle) {

      // Local variables
      var dx = b.pos.x - a.pos.x
      var dy = b.pos.y - a.pos.y
      let vdx = b.vel.x - a.vel.x
      let vdy = b.vel.y - a.vel.y
      let a_vel = a.vel
      let b_vel = b.vel
      let m1 = a.mass
      let m2 = b.mass

      // Should the circles intersect. Seperate them. If not the next
      // calculated values will be off.
      separate(&a, &b)

      // A negative 'd' means the circles velocities are in opposite directions
      let d = dx * vdx + dy * vdy

      // Rotation response
      // w is the torque, r is the vector to the collision point from the center, v is the velocity vector
      // ω = (cross(cp, v1) / r1 * friction + w2 * 0.1; r.x*v.y−r.y*v.x) / (r2x+r2y)
      //
        let ar = a.radius
        let br = b.radius
        
        let collision_depth = distance(b.pos, a.pos)

        // contact angle

        dx = b.pos.x - a.pos.x
        dy = b.pos.y - a.pos.y

        let collision_angle = atan2(dy, dx)
        let cos_angle = cos(collision_angle)
        let sin_angle = sin(collision_angle)

         let r1 = float2( collision_depth * 0.5 * cos_angle,  collision_depth * 0.5 *  sin_angle)
         let r2 = float2(-collision_depth * 0.5 * cos_angle, -collision_depth * 0.5 *  sin_angle)
         let v1 = a.vel
         let v2 = b.vel
        
        func cross(_ v1: float2, _ v2: float2) -> Float {
            return (v1.x*v2.y) - (v1.y*v2.x)
        }

        // const auto cross = [](const vec2 & v1, const vec2 & v2)
        // {
        //   return (v1.x*v2.y) - (v1.y*v2.x);
        // };

        let friction: Float = 0.1

         a.torque = (cross(normalize(r2), v1) / ar) * friction + b.torque * 0.5
         b.torque = (cross(normalize(r1), v2) / br) * friction + a.torque * 0.5

      // And we don't resolve collisions between circles moving away from eachother
      if (d < 1e-11) {
        let norm = normalize(float2(dx, dy))
        let tang = float2(norm.y * -1.0, norm.x)
        let scal_norm_1 = dot(norm, a_vel)
        let scal_norm_2 = dot(norm, b_vel)
        let scal_tang_1 = dot(tang, a_vel)
        let scal_tang_2 = dot(tang, b_vel)

        let scal_norm_1_after = (scal_norm_1 * (m1 - m2) + 2.0 * m2 * scal_norm_2) / (m1 + m2)
        let scal_norm_2_after = (scal_norm_2 * (m2 - m1) + 2.0 * m1 * scal_norm_1) / (m1 + m2)
        let scal_norm_1_after_vec = norm * scal_norm_1_after
        let scal_norm_2_after_vec = norm * scal_norm_2_after
        let scal_norm_1_vec = tang * scal_tang_1
        let scal_norm_2_vec = tang * scal_tang_2

        // Update velocities
        a.vel = (scal_norm_1_vec + scal_norm_1_after_vec) * collisionEnergyLoss
        b.vel = (scal_norm_2_vec + scal_norm_2_after_vec) * collisionEnergyLoss
      }
    }


    // Separates two intersecting circles.
    func separate(_ a: inout Particle, _ b: inout Particle) {
      // Local variables
      let a_pos = a.pos
      let b_pos = b.pos
      let ar = a.radius
      let br = b.radius

      let collision_depth = (ar + br) - distance(b_pos, a_pos)

        if (collision_depth < 1e-11) { return }

      let dx = b_pos.x - a_pos.x
      let dy = b_pos.y - a_pos.y

      // contact angle
      let collision_angle = atan2(dy, dx)
      let cos_angle = cos(collision_angle)
      let sin_angle = sin(collision_angle)

      // @Same as above, just janky not working
      // const auto midpoint_x = (a_pos.x + b_pos.x) / 2.0f;
      // const auto midpoint_y = (a_pos.y + b_pos.y) / 2.0f;

      // TODO: could this be done using a normal vector and just inverting it?
      // amount to move each ball

      var a_move = float2( -collision_depth * 0.5 * cos_angle,  -collision_depth * 0.5 * sin_angle)
      var b_move = float2(  collision_depth * 0.5 * cos_angle,   collision_depth * 0.5 * sin_angle)

      // @Same as above, just janky not working
      // const f32 a_move.x = midpoint_x + ar * (a_pos.x - b_pos.x) / collision_depth;
      // const f32 a_move.y = midpoint_y + ar * (a_pos.y - b_pos.y) / collision_depth;
      // const f32 b_move.x = midpoint_x + br * (b_pos.x - a_pos.x) / collision_depth;
      // const f32 b_move.y = midpoint_y + br * (b_pos.y - a_pos.y) / collision_depth;

      // stores the position offsets
      var a_pos_move = float2(0)
      var b_pos_move = float2(0)

      // Make sure they dont moved beyond the border
      // This will become not needed when borders are
      //  segments instead of hardcoded.
      if (a_pos.x + a_move.x >= 0.0 + ar && a_pos.x + a_move.x <= framebufferWidth - ar) {
        a_pos_move.x += a_move.x
      }
      if (a_pos.y + a_move.y >= 0.0 + ar && a_pos.y + a_move.y <= framebufferHeight - ar) {
        a_pos_move.y += a_move.y
      }
      if (b_pos.x + b_move.x >= 0.0 + br && b_pos.x + b_move.x <= framebufferWidth - br) {
        b_pos_move.x += b_move.x
      }
      if (b_pos.y + b_move.y >= 0.0 + br && b_pos.y + b_move.y <= framebufferHeight - br) {
        b_pos_move.y += b_move.y
      }

      // Update positions
      a.pos += a_pos_move
      b.pos += b_pos_move
    }
    
}
