//
//  ParticleSystem.swift
//  Athi
//
//  Created by Marcus Mathiassen on 04/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

import MetalKit
import simd
import MetalPerformanceShaders

struct Particle
{
    var id: Int = 0
    var pos = float2(0)
    var vel = float2(0)
    var radius: Float = 1
    var mass: Float = 0

    mutating func borderCollision() {
        // Border collision
        if pos.x < 0 + radius {
            pos.x = 0 + radius
            vel.x = -vel.x
        }
        if pos.x > framebufferWidth - radius {
            pos.x = framebufferWidth - radius
            vel.x = -vel.x
        }
        if pos.y < 0 + radius {
            pos.y = 0 + radius
            vel.y = -vel.y
        }
        if pos.y > framebufferHeight - radius {
            pos.y = framebufferHeight - radius
            vel.y = -vel.y
        }
    }

    mutating func update() {
        // Update pos/vel
        pos += vel
    }
}

final class ParticleSystem
{
    /**
        Particle data for the CPU
     */
    var particles: [Particle] = []
    
    
    struct ParticleData
    {
        var position: float2
        var color:    float4
        var size:     Float
    }
    
    /**
        Particle data for the GPU
     */
    private var particleData: [ParticleData] = []
    
    // Options
    private var shouldUpdate: Bool = false
    
    
    var enableMultithreading: Bool = true
    var enableBorderCollision: Bool = true
    var collisionEnergyLoss: Float = 0.98
    var gravityForce: Float = -0.981
    var enableGravity: Bool = false
    var enableCollisions: Bool = true
    var useAccelerometerAsGravity: Bool = false
    var useQuadtree: Bool = true
    var hasInitialVelocity: Bool = true
    var useTreeOptimalSize: Bool = true
    
    var enablePostProcessing: Bool = true
    var postProcessingSamples: Int = 2
    var blurStrength: Float = 4

    
    var preAllocatedParticles = 100
    private var allocatedMemoryForParticles: Int
    
    
    #if os(macOS)
    private var dynamicBufferResourceOption: MTLResourceOptions = .cpuCacheModeWriteCombined
    private var staticBufferResourceOption: MTLResourceOptions = .storageModeShared
    #else
    private var dynamicBufferResourceOption: MTLResourceOptions = .cpuCacheModeWriteCombined
    private var staticBufferResourceOption: MTLResourceOptions = .storageModeShared
    #endif
    
    var samples: Int = 1
    
    var isPaused: Bool = false
    
    var particleColor = float4(1)
    
    
    var numVerticesPerParticle = 36
    
    /**
        Static data uploaded once, and updated when numVerticesPerParticle is changed
     */
    private var vertices: [float2] = []
    private var indices: [UInt16] = []
    /**
        Dynamic data updated each frame. Each element represents the color of a single particle
     */
    private var colors: [float4] = []
    
    private var tempGravityForce = float2(0)

    private var listOfNodesOfIDs: [[Int]] = []
    private var quadtree: Quadtree?
    private var quad: Quad

    // Metal stuff
    private var device: MTLDevice
    private var particleDataBuffer: MTLBuffer
    private var vertexBuffer: MTLBuffer
    private var indexBuffer: MTLBuffer
    private var pipelineState: MTLRenderPipelineState?
    var texture0: MTLTexture
    var texture1: MTLTexture

    init(device: MTLDevice)
    {
        self.device = device
        quad = Quad(device: device)

        let library = device.makeDefaultLibrary()!
        let vertexFunc = library.makeFunction(name: "particleVert")!
        let fragFunc = library.makeFunction(name: "particleFrag")!
        
        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.label = "pipelineDesc"
        pipelineDesc.vertexFunction = vertexFunc
        pipelineDesc.fragmentFunction = fragFunc
        pipelineDesc.colorAttachments[0].pixelFormat = Renderer.pixelFormat
        pipelineDesc.colorAttachments[1].pixelFormat = Renderer.pixelFormat

        do {
            try pipelineState = device.makeRenderPipelineState(descriptor: pipelineDesc)
        } catch {
            print("ParticleSystem Pipeline: Creating pipeline state failed")
        }
        
        
        allocatedMemoryForParticles = preAllocatedParticles
        particleDataBuffer = device.makeBuffer(length: allocatedMemoryForParticles * MemoryLayout<ParticleData>.stride, options: dynamicBufferResourceOption)!
        vertexBuffer = device.makeBuffer(length: MemoryLayout<float2>.stride * numVerticesPerParticle, options: staticBufferResourceOption)!
        indexBuffer = device.makeBuffer(length: MemoryLayout<UInt16>.stride * numVerticesPerParticle*3, options: staticBufferResourceOption)!

        let mainTextureDesc = MTLTextureDescriptor()
        mainTextureDesc.height = Int(framebufferHeight)
        mainTextureDesc.width = Int(framebufferWidth)
        mainTextureDesc.sampleCount = 1
        mainTextureDesc.textureType = .type2D
        mainTextureDesc.pixelFormat = Renderer.pixelFormat
        mainTextureDesc.resourceOptions = .storageModePrivate
        mainTextureDesc.usage = .renderTarget
        texture0 = device.makeTexture(descriptor: mainTextureDesc)!
        texture1 = device.makeTexture(descriptor: mainTextureDesc)!
        
        buildVertices(numVertices: numVerticesPerParticle)
    }

    public func draw(view: MTKView,
                     commandBuffer: MTLCommandBuffer)
    {
        
        commandBuffer.pushDebugGroup("ParticleSystem Draw")
        
        var renderPassDesc = MTLRenderPassDescriptor()
        renderPassDesc.colorAttachments[0].clearColor = Renderer.clearColor
        renderPassDesc.colorAttachments[0].texture = texture0
        renderPassDesc.colorAttachments[0].loadAction = .clear
        renderPassDesc.colorAttachments[0].storeAction = .store
        
        renderPassDesc.colorAttachments[1].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        renderPassDesc.colorAttachments[1].texture = texture1
        renderPassDesc.colorAttachments[1].loadAction = .clear
        renderPassDesc.colorAttachments[1].storeAction = .store
        
        var renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc)!

        renderEncoder.pushDebugGroup("Draw particles (off-screen)")
        renderEncoder.setRenderPipelineState(pipelineState!)
        
        updateGPUBuffers()
        
        renderEncoder.setVertexBuffer(vertexBuffer,           offset: 0, index: 0)
        renderEncoder.setVertexBuffer(particleDataBuffer,     offset: 0, index: 1)
        renderEncoder.setVertexBytes(&viewportSize,    length: MemoryLayout<float2>.stride, index: 2)

        renderEncoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: indices.count,
            indexType: .uint16,
            indexBuffer: indexBuffer,
            indexBufferOffset: 0,
            instanceCount: particleData.count)
        
        
        if enablePostProcessing {
            
            renderEncoder.pushDebugGroup("Apply Post Processing")
            quad.gaussianBlur(renderEncoder: renderEncoder, texture: texture0, sigma: blurStrength, samples: postProcessingSamples)
            renderEncoder.popDebugGroup()
            
            
            renderEncoder.pushDebugGroup("Overlay the unblurred original")
            quad.draw(renderEncoder: renderEncoder, texture: texture1)
            renderEncoder.popDebugGroup()

        }
        
        renderEncoder.popDebugGroup()
        renderEncoder.endEncoding()
        
        
        renderPassDesc = view.currentRenderPassDescriptor!
        renderPassDesc.colorAttachments[0].clearColor = Renderer.clearColor
        renderPassDesc.colorAttachments[0].loadAction = .clear
        renderPassDesc.colorAttachments[0].storeAction = .store
        renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc)!
        
        renderEncoder.pushDebugGroup("Draw particles (on-screen)")
        quad.draw(renderEncoder: renderEncoder, texture: texture0)
        
        renderEncoder.popDebugGroup()
        renderEncoder.endEncoding()
        
        commandBuffer.popDebugGroup()
    }
    
    private func updateGPUBuffers()
    {
        // Reallocate more if needed
        if particleData.count * MemoryLayout<ParticleData>.stride > particleDataBuffer.allocatedSize {
            
            // Update the buffer size
            particleDataBuffer = device.makeBuffer(length: particleData.count * MemoryLayout<ParticleData>.stride, options: dynamicBufferResourceOption)!
            
            // Upload new content
            particleDataBuffer.contents().copyMemory(from: particleData, byteCount: particleData.count * MemoryLayout<ParticleData>.stride)

        } else {
            
            // Upload new content
            particleDataBuffer.contents().copyMemory(from: particleData, byteCount: particleData.count * MemoryLayout<ParticleData>.stride)
        }
    }

    public func update()
    {
        if isPaused { return }
        
        if shouldUpdate {
            buildVertices(numVertices: numVerticesPerParticle)
            shouldUpdate = false
        }

        if enableCollisions {
            for _ in 0 ..< samples
            {
                if enableMultithreading
                {
                    if useQuadtree
                    {
                        // Clear the nodes
                        listOfNodesOfIDs.removeAll()

                        var min: float2
                        var max: float2
                        if useTreeOptimalSize {
                            let (mi, ma) = getMinAndMaxPosition()
                            min = mi
                            max = ma
                            quadtree = Quadtree(min: min, max: max)
                        } else {
                            quadtree = Quadtree(min: float2(0, 0), max: float2(framebufferWidth, framebufferHeight))
                        }

                        quadtree?.input(data: particles)

                        quadtree?.getNodesOfIndices(containerOfNodes: &listOfNodesOfIDs)

//                        DispatchQueue.concurrentPerform(iterations: 8) { i in
//                                                let (begin, end) = getBeginAndEnd(i: i, containerSize: listOfNodesOfIDs.count, segments: 8)
//                                                collisionQuadtree(containerOfNodes: listOfNodesOfIDs, begin: begin, end: end)
//                                            }
                        collisionQuadtree(containerOfNodes: listOfNodesOfIDs, begin: 0, end: listOfNodesOfIDs.count)

                    } else { collisionLogNxN(total: particles.count, begin: 0, end: particles.count) }
                    
                } else {
                    if useQuadtree {
                        // Clear the nodes
                        listOfNodesOfIDs.removeAll()

                        var min: float2
                        var max: float2
                        if useTreeOptimalSize {
                            let (mi, ma) = getMinAndMaxPosition()
                            min = mi
                            max = ma
                            quadtree = Quadtree(min: min, max: max)
                        } else {
                            quadtree = Quadtree(min: float2(0, 0), max: float2(framebufferWidth, framebufferHeight))
                        }

                        quadtree?.input(data: particles)

                        quadtree?.getNodesOfIndices(containerOfNodes: &listOfNodesOfIDs)

                        collisionQuadtree(containerOfNodes: listOfNodesOfIDs, begin: 0, end: listOfNodesOfIDs.count)

                    } else { collisionLogNxN(total: particles.count, begin: 0, end: particles.count) }
                }
            }
        }

        if enableGravity {
            if useAccelerometerAsGravity {
                tempGravityForce = float2(accelerometer.x, accelerometer.y)
            } else {
                tempGravityForce.y = gravityForce
            }
        } else {
            tempGravityForce *= 0
        }

        
        if enableMultithreading {
            DispatchQueue.concurrentPerform(iterations: 8) { i in
                let (begin, end) = getBeginAndEnd(i: i, containerSize: particles.count, segments: 8)
                updateParticlesData(begin: begin, end: end)
            }
        } else {
            updateParticlesData(begin: 0, end: particles.count)
        }
    }

    public func setVerticesPerParticle(num: Int)
    {
        numVerticesPerParticle = num
        shouldUpdate = true
    }

    private func buildVertices(numVertices: Int) {
        
        // We cant draw anything with less than 3 vertices so just return
        if numVertices < 3 { return }
        
        // Clear previous values
        vertices.removeAll()
        indices.removeAll()
        
        // Add indices
        for n in 0 ..< numVertices - 2 {
            indices.append(UInt16(0))
            indices.append(UInt16(n + 1))
            indices.append(UInt16(n + 2))
        }

        // Add vertices
        for i in 0 ..< numVertices {
                let cont = Float(i) * Float.pi * 2 / Float(numVertices)
                let x = cos(cont)
                let y = sin(cont)
                vertices.append(float2(x, y))
        }
        
        
        // Update the GPU buffers
        vertexBuffer = device.makeBuffer(bytes: vertices, length: MemoryLayout<float2>.stride * vertices.count, options: staticBufferResourceOption)!
        indexBuffer = device.makeBuffer(bytes: indices, length: MemoryLayout<UInt16>.stride * indices.count, options: staticBufferResourceOption)!
    }

    private func collisionCheck(_ a: Particle, _ b: Particle) -> Bool
    {
        // Local variables
        let ax = a.pos.x
        let ay = a.pos.y
        let bx = b.pos.x
        let by = b.pos.y
        let ar = a.radius
        let br = b.radius

        // square collision check
        if ax - ar < bx + br &&
            ax + ar > bx - br &&
            ay - ar < by + br &&
            ay + ar > by - br {
            // circle collision check
            let dx = bx - ax
            let dy = by - ay

            let sum_radius = ar + br
            let sqr_radius = sum_radius * sum_radius

            let distance_sqrd = (dx * dx) + (dy * dy)

            return distance_sqrd < sqr_radius
        }

        return false
    }

    // Collisions response between two circles with varying radius and mass.
    private func collisionResolve(_ a: inout Particle, _ b: inout Particle) {
        // Local variables
        let dx = b.pos.x - a.pos.x
        let dy = b.pos.y - a.pos.y
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

        // And we don't resolve collisions between circles moving away from eachother
        if d < 1e-11 {
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
    private func separate(_ a: inout Particle, _ b: inout Particle) {
        // Local variables
        let a_pos = a.pos
        let b_pos = b.pos
        let ar = a.radius
        let br = b.radius

        let collision_depth = (ar + br) - distance(b_pos, a_pos)

        if collision_depth < 1e-11 { return }

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

        var a_move = float2(-collision_depth * 0.5 * cos_angle, -collision_depth * 0.5 * sin_angle)
        var b_move = float2(collision_depth * 0.5 * cos_angle, collision_depth * 0.5 * sin_angle)

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
        if a_pos.x + a_move.x >= 0.0 + ar && a_pos.x + a_move.x <= framebufferWidth - ar {
            a_pos_move.x += a_move.x
        }
        if a_pos.y + a_move.y >= 0.0 + ar && a_pos.y + a_move.y <= framebufferHeight - ar {
            a_pos_move.y += a_move.y
        }
        if b_pos.x + b_move.x >= 0.0 + br && b_pos.x + b_move.x <= framebufferWidth - br {
            b_pos_move.x += b_move.x
        }
        if b_pos.y + b_move.y >= 0.0 + br && b_pos.y + b_move.y <= framebufferHeight - br {
            b_pos_move.y += b_move.y
        }

        // Update positions
        a.pos += a_pos_move
        b.pos += b_pos_move
    }

    private func updateParticlesData(begin: Int, end: Int) {
        for i in begin ..< end {
            var p = particles[i]

            p.vel += tempGravityForce
            p.borderCollision()
            p.update()

            particles[i] = p

            // Update particleData
            particleData[i] = ParticleData(position: p.pos, color: colors[p.id], size: p.radius)
        }
    }
    
    public func removeFirst(_ i: Int) {
        particles.removeFirst(i)
        particleData.removeFirst(i)
        colors.removeFirst(i)
    }

    public func eraseParticles() {
        particles.removeAll()
        particleData.removeAll()
        colors.removeAll()
    }
    
    public func colorParticles(IDs: [Int], color: float4)
    {
        for id in IDs {
            colors[id] = color
        }
    }

    public func addParticle(_ p: Particle, color: float4) {
        var pa = p
        pa.id = particles.count

        // Add new particle
        particles.append(pa)
        
        // Add it to be drawn
        let pD = ParticleData(position: p.pos, color: color, size: p.radius)
        particleData.append(pD)
        
        // Add new color
        colors.append(color)
    }
    
    public func addParticle(position: float2, color: float4, radius: Float) {
        
        var p = Particle()
        p.id = particles.count
        p.pos = position
        if hasInitialVelocity { p.vel = randFloat2(-5, 5) }
        p.radius = radius
        p.mass = Float.pi * radius * radius

        // Add new particle
        particles.append(p)
        
        // Add it to be drawn
        let pD = ParticleData(position: position, color: color, size: radius)
        particleData.append(pD)
        
        colors.append(color)
    }

    private func collisionQuadtree(containerOfNodes: [[Int]], begin: Int, end: Int) {
        for k in begin ..< end {
            for i in 0 ..< containerOfNodes[k].count {
                for j in 1 + i ..< containerOfNodes[k].count {
                    if collisionCheck(particles[containerOfNodes[k][i]], particles[containerOfNodes[k][j]]) {
                        collisionResolve(&particles[containerOfNodes[k][i]], &particles[containerOfNodes[k][j]])
                    }
                }
            }
        }
    }

    private func collisionLogNxN(total: Int, begin: Int, end: Int) {
        for i in begin ..< end {
            for j in 1 + i ..< total {
                if collisionCheck(particles[i], particles[j]) {
                    collisionResolve(&particles[i], &particles[j])
                }
            }
        }
    }

    /**
     Returns an array of ids that fit inside the circle
     */
    public func getParticlesInCircle(position: float2, radius: Float) -> [Int] {
        var ids: [Int] = []

        var p = Particle()
        p.pos = position
        p.radius = radius

        // Brute-force
        for otherParticle in particles {
            if collisionCheck(p, otherParticle) {
                ids.append(otherParticle.id)
            }
        }

        return ids
    }

    /**
     Returns the minimum and maximum position found of all particles
     */
    public func getMinAndMaxPosition() -> (float2, float2) {
        var max = float2(Float((-INT_MAX)), Float(-INT_MAX))
        var min = float2(Float(INT_MAX), Float(INT_MAX))

        for p in particles {
            max.x = (p.pos.x > max.x) ? p.pos.x : max.x
            max.y = (p.pos.y > max.y) ? p.pos.y : max.y
            min.x = (p.pos.x < min.x) ? p.pos.x : min.x
            min.y = (p.pos.y < min.y) ? p.pos.y : min.y
        }

        return (min, max)
    }

    private func gravityWell(a: inout Particle, point: float2) {
        let x1 = a.pos.x
        let y1 = a.pos.y
        let x2 = point.x
        let y2 = point.y
        let m1 = a.mass
        let m2 = Float(1e6)

        let dx = x2 - x1
        let dy = y2 - y1
        let d = sqrt(dx * dx + dy * dy)

        let angle = atan2(dy, dx)
        let G = Float(kGravitationalConstant)
        let F = G * m1 * m2 / d * d

        a.vel.x += F * cos(angle)
        a.vel.y += F * sin(angle)
    }
    
    public func goTowardsPoint(_ point: float2, force: Float)
    {
        for id in 0 ..< particles.count {
            attractionForce(p: &particles[id], point: point, force: force)
        }
    }
    public func goTowardsPoint(_ point: float2, particleIDs: inout [Int])
    {
        for id in particleIDs {
            attractionForce(p: &particles[id], point: point)
        }
    }

    public func attractionForce(p: inout Particle, point: float2, force: Float) {
        let x1 = p.pos.x
        let y1 = p.pos.y
        let x2 = point.x
        let y2 = point.y
        let m1 = p.mass
        let m2 = Float(1e11)
        
        let dx = x2 - x1
        let dy = y2 - y1
        let d = sqrt(dx * dx + dy * dy)
        
        let angle = atan2(dy, dx)
        let G = Float(kGravitationalConstant)
        let F = G * m1 * m2 / d * d
        
        p.vel.x += F * cos(angle)
        p.vel.y += F * sin(angle)
    }
    public func attractionForce(p: inout Particle, point: float2) {
        // Set up variables
        let x1: Float = p.pos.x
        let y1: Float = p.pos.y
        let x2: Float = point.x
        let y2: Float = point.y

        // Get distance between balls.
        let dx: Float = x2 - x1
        let dy: Float = y2 - y1
        let d: Float = sqrt(dx * dx + dy * dy)

        let angle: Float = atan2(dy, dx)
        p.vel.x += d * cos(angle)
        p.vel.y += d * sin(angle)
        p.vel *= 0.05
    }
}
