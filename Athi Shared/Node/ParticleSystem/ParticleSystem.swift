//
//  ParticleSystem.swift
//  Athi
//
//  Created by Marcus Mathiassen on 04/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

import Metal
import MetalKit
import simd
import MetalPerformanceShaders

final class ParticleSystem
{
    ///////////////////
    // Simulation
    ///////////////////
    
    public var particleCount: Int = 0 // Amount of particles
    
    //      Particle data
    var id:         [Int] = []
    var position:   [float2] = []
    var velocity:   [float2] = []
    var radius:     [Float] = []
    var mass:       [Float] = []
    var color:      [float4] = []
    //
    
    // Options
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
    
    var samples: Int = 1
    var isPaused: Bool = false
    
    private var tempGravityForce = float2(0)
    private var shouldUpdate: Bool = false
    private var listOfNodesOfIDs: [[Int]] = []
    private var quadtree: Quadtree?
    private var quadtreeV2: QuadtreeV2?

    
    ///////////////////
    // Rendering
    ///////////////////
    
    // @GPU: Data needed to draw the particles
    struct ParticleGPU
    {
        var position: float2
        var color:    float4
        var radius:   Float
    }

    /**
        Particle data for the GPU
     */
    var particleData: [ParticleGPU] = []
    
    /**
        Static data uploaded once, and updated when numVerticesPerParticle is changed
     */
    private var vertices: [float2] = []
    private var indices: [UInt16] = []

    // Metal stuff
    // Rendering stuff
    
    
    var computePipelineState: MTLComputePipelineState?
    
    var enablePostProcessing: Bool = true
    var postProcessingSamples: Int = 1
    var blurStrength: Float = 2
    var preAllocatedParticles = 100
    private var allocatedMemoryForParticles: Int
    #if os(macOS)
    private var dynamicBufferResourceOption: MTLResourceOptions = .cpuCacheModeWriteCombined
    private var staticBufferResourceOption: MTLResourceOptions = .storageModeShared
    #else
    private var dynamicBufferResourceOption: MTLResourceOptions = .cpuCacheModeWriteCombined
    private var staticBufferResourceOption: MTLResourceOptions = .storageModeShared
    #endif
    var particleColor = float4(1)
    var numVerticesPerParticle = 36
    private var quad: Quad
    private var device: MTLDevice
    private var particleDataBuffer: MTLBuffer
    private var vertexBuffer: MTLBuffer
    private var indexBuffer: MTLBuffer
    private var pipelineState: MTLRenderPipelineState?
    
    var inTexture: MTLTexture
    var outTexture: MTLTexture
    var finalTexture: MTLTexture

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
        particleDataBuffer = device.makeBuffer(length: allocatedMemoryForParticles * MemoryLayout<ParticleGPU>.stride, options: dynamicBufferResourceOption)!
        vertexBuffer = device.makeBuffer(length: MemoryLayout<float2>.stride * numVerticesPerParticle, options: staticBufferResourceOption)!
        indexBuffer = device.makeBuffer(length: MemoryLayout<UInt16>.stride * numVerticesPerParticle*3, options: staticBufferResourceOption)!

        let inTextureDesc = MTLTextureDescriptor()
        inTextureDesc.height = Int(framebufferHeight)
        inTextureDesc.width = Int(framebufferWidth)
        inTextureDesc.sampleCount = 1
        inTextureDesc.textureType = .type2D
        inTextureDesc.pixelFormat = Renderer.pixelFormat
        inTextureDesc.resourceOptions = .storageModePrivate
        inTextureDesc.usage = .shaderRead
        inTexture = device.makeTexture(descriptor: inTextureDesc)!
        
        let outTextureDesc = MTLTextureDescriptor()
        outTextureDesc.height = Int(framebufferHeight)
        outTextureDesc.width = Int(framebufferWidth)
        outTextureDesc.sampleCount = 1
        outTextureDesc.textureType = .type2D
        outTextureDesc.pixelFormat = Renderer.pixelFormat
        outTextureDesc.resourceOptions = .storageModePrivate
        outTextureDesc.usage = .shaderWrite
        outTexture = device.makeTexture(descriptor: outTextureDesc)!
        
        finalTexture = device.makeTexture(descriptor: outTextureDesc)!
        
        buildVertices(numVertices: numVerticesPerParticle)
    }

    public func draw(view: MTKView,
                     commandBuffer: MTLCommandBuffer)
    {
        if particleCount == 0 { return }
        
        commandBuffer.pushDebugGroup("ParticleSystem Draw")
        
        var renderPassDesc = MTLRenderPassDescriptor()
        renderPassDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        renderPassDesc.colorAttachments[0].texture = inTexture
        renderPassDesc.colorAttachments[0].loadAction = .clear
        renderPassDesc.colorAttachments[0].storeAction = .store
        
        renderPassDesc.colorAttachments[1].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        renderPassDesc.colorAttachments[1].texture = finalTexture
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
        
        renderEncoder.popDebugGroup()
        renderEncoder.endEncoding()
        
        if enablePostProcessing {
            
            renderEncoder.pushDebugGroup("Apply Post Processing")

            
            let blurKernel = MPSImageGaussianBlur(device: device, sigma: blurStrength)
            blurKernel.encode(commandBuffer: commandBuffer,
                              sourceTexture: inTexture,
                              destinationTexture: outTexture)

            quad.mix(commandBuffer: commandBuffer, inputTexture1: inTexture, inputTexture2: outTexture, outTexture: finalTexture, sigma: 5.0)
            
//
//            quad.pixelate(commandBuffer: commandBuffer, inputTexture: inTexture, outputTexture: finalTexture, sigma: blurStrength)

            renderEncoder.popDebugGroup()
        }
        
        
        renderPassDesc = view.currentRenderPassDescriptor!
        renderPassDesc.colorAttachments[0].clearColor = Renderer.clearColor
        renderPassDesc.colorAttachments[0].loadAction = .clear
        renderPassDesc.colorAttachments[0].storeAction = .store
        renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc)!
        
        renderEncoder.pushDebugGroup("Draw particles (on-screen)")
        
        quad.draw(renderEncoder: renderEncoder, texture: finalTexture)
        
        renderEncoder.popDebugGroup()
        renderEncoder.endEncoding()
        
        commandBuffer.popDebugGroup()
    }
    
    private func updateGPUBuffers()
    {
        // Reallocate more if needed
        if particleData.count * MemoryLayout<ParticleGPU>.stride > particleDataBuffer.allocatedSize {
            
            // Update the buffer size
            particleDataBuffer = device.makeBuffer(length: particleData.count * MemoryLayout<ParticleGPU>.stride, options: dynamicBufferResourceOption)!
            
            // Upload new content
            particleDataBuffer.contents().copyMemory(from: particleData, byteCount: particleData.count * MemoryLayout<ParticleGPU>.stride)

        } else {
            
            // Upload new content
            particleDataBuffer.contents().copyMemory(from: particleData, byteCount: particleData.count * MemoryLayout<ParticleGPU>.stride)
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
//                            quadtreeV2 = QuadtreeV2(bounds: Rect(min: min, max: max), maxCapacity: 5, maxDepth: 3)

                        } else {
//                            quadtreeV2 = QuadtreeV2(bounds: Rect(min: float2(0, 0), max: float2(framebufferWidth, framebufferHeight)), maxCapacity: 50, maxDepth: 5)
                            quadtree = Quadtree(min: float2(0, 0), max: float2(framebufferWidth, framebufferHeight))
                        }
//
//                        quadtreeV2?.setData(positionData: position, radiiData: radius)
//                        quadtreeV2?.insertRange(0 ... particleCount)
//                        quadtreeV2?.getNodesOfIndices(containerOfNodes: &listOfNodesOfIDs)
//
                        quadtree?.setInputData(positions: position, radii: radius)
                        quadtree?.inputRange(range: 0 ... particleCount)

                        quadtree?.getNodesOfIndices(containerOfNodes: &listOfNodesOfIDs)

//                        DispatchQueue.concurrentPerform(iterations: 8) { i in
//                                                let (begin, end) = getBeginAndEnd(i: i, containerSize: listOfNodesOfIDs.count, segments: 8)
//                                                collisionQuadtree(containerOfNodes: listOfNodesOfIDs, begin: begin, end: end)
//                                            }
                        collisionQuadtree(containerOfNodes: listOfNodesOfIDs, begin: 0, end: listOfNodesOfIDs.count)

                    } else { collisionLogNxN(total: particleCount, begin: 0, end: particleCount) }
                    
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

                        quadtree?.setInputData(positions: position, radii: radius)
                        quadtree?.inputRange(range: 0 ... particleCount)

                        quadtree?.getNodesOfIndices(containerOfNodes: &listOfNodesOfIDs)

                        collisionQuadtree(containerOfNodes: listOfNodesOfIDs, begin: 0, end: listOfNodesOfIDs.count)

                    } else {
                        collisionLogNxN(total: particleCount, begin: 0, end: particleCount)
                    }
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
//            DispatchQueue.concurrentPerform(iterations: 8) { i in
//                let (begin, end) = getBeginAndEnd(i: i, containerSize: particleCount, segments: 8)
//                print(begin, end)
//                updateParticlesData(begin: begin, end: end)
//            }
            updateParticlesData(begin: 0, end: particleCount)

        } else {
            updateParticlesData(begin: 0, end: particleCount)
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
    
    
    //
    private func updateParticlesData(begin: Int, end: Int)
    {
        
        for i in begin ..< end {
            
            var p = self.position[i]
            var v = self.velocity[i]
            let r = self.radius[i]
            
            // Border collision
            if p.x < 0 + r {
                p.x = 0 + r
                v.x = -v.x
            }
            if p.x > framebufferWidth - r {
                p.x = framebufferWidth - r
                v.x = -v.x
            }
            if p.y < 0 + r {
                p.y = 0 + r
                v.y = -v.y
            }
            if p.y > framebufferHeight - r {
                p.y = framebufferHeight - r
                v.y = -v.y
            }
            velocity[i] = v
            position[i] = p
            
            // Update particle positions
            position[i] += velocity[i]
            
            particleData[i] = ParticleGPU(position: position[i], color: color[i], radius: radius[i])
        }
    }
    
    public func eraseParticles()
    {
        position.removeAll()
        velocity.removeAll()
        mass.removeAll()
        radius.removeAll()
        color.removeAll()
        
        
        // Rendering data
        particleData.removeAll()
        
        particleCount = 0
    }
    
    public func colorParticles(IDs: [Int], color: float4)
    {
        for id in IDs {
            self.color[id] = color
        }
    }

    ////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////
    //////////  PHYSICS
    ////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////
    
    private func collisionCheck(_ a: Int, position: float2, radius: Float) -> Bool
    {
        // Local variables
        let ax = self.position[a].x
        let ay = self.position[a].y
        let bx = position.x
        let by = position.y
        let ar = self.radius[a]
        let br = radius
        
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
    
    private func collisionCheck(_ a: Int, _ b: Int) -> Bool
    {
        // Local variables
        let ax = position[a].x
        let ay = position[a].y
        let bx = position[b].x
        let by = position[b].y
        let ar = radius[a]
        let br = radius[b]
        
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
    
    private func collisionResolve(_ a: Int, _ b: Int) -> (float2, float2)
    {
        // Local variables
        let dx = position[b].x - position[a].x
        let dy = position[b].y - position[a].y
        let vdx = velocity[b].x - velocity[a].x
        let vdy = velocity[b].y - velocity[a].y
        let v1 = velocity[a]
        let v2 = velocity[b]
        let m1 = mass[a]
        let m2 = mass[b]
        
        // A negative 'd' means the circles velocities are in opposite directions
        let d = dx * vdx + dy * vdy
        
        // And we don't resolve collisions between circles moving away from eachother
        if d < 1e-11 {
            let norm = normalize(float2(dx, dy))
            let tang = float2(norm.y * -1.0, norm.x)
            let scal_norm_1 = dot(norm, v1)
            let scal_norm_2 = dot(norm, v2)
            let scal_tang_1 = dot(tang, v1)
            let scal_tang_2 = dot(tang, v2)
            
            let scal_norm_1_after = (scal_norm_1 * (m1 - m2) + 2.0 * m2 * scal_norm_2) / (m1 + m2)
            let scal_norm_2_after = (scal_norm_2 * (m2 - m1) + 2.0 * m1 * scal_norm_1) / (m1 + m2)
            let scal_norm_1_after_vec = norm * scal_norm_1_after
            let scal_norm_2_after_vec = norm * scal_norm_2_after
            let scal_norm_1_vec = tang * scal_tang_1
            let scal_norm_2_vec = tang * scal_tang_2
            
            // Update velocities
            return ((scal_norm_1_vec + scal_norm_1_after_vec) * 0.98, (scal_norm_2_vec + scal_norm_2_after_vec) * 0.98)
        }
        
        return (v1, v2)
    }
    
    
    // Separates two intersecting circles.
    private func separate(_ a: Int, _ b: Int) -> (float2, float2)
    {
        // Local variables
        let ap = position[a]
        let bp = position[b]
        let ar = radius[a]
        let br = radius[b]
        
        let collisionDepth = (ar + br) - distance(bp, ap)
        
        let dx = bp.x - ap.x
        let dy = bp.y - bp.y
        
        // contact angle
        let collisionAngle = atan2(dy, dx)
        let cosAngle = cos(collisionAngle)
        let sinAngle = sin(collisionAngle)
        
        let aMove = float2(-collisionDepth * 0.5 * cosAngle, -collisionDepth * 0.5 * sinAngle)
        let bMove = float2( collisionDepth * 0.5 * cosAngle,  collisionDepth * 0.5 * sinAngle)
        
        // stores the position offsets
        var apNew = float2(0)
        var bpNew = float2(0)
        
        // Make sure they dont moved beyond the border
        // This will become not needed when borders are segments instead of hardcoded.
        if ap.x + aMove.x >= 0.0 + ar && ap.x + aMove.x <= framebufferWidth - ar {
            apNew.x += aMove.x
        }
        if ap.y + aMove.y >= 0.0 + ar && ap.y + aMove.y <= framebufferHeight - ar {
            apNew.y += aMove.y
        }
        if bp.x + bMove.x >= 0.0 + br && bp.x + bMove.x <= framebufferWidth - br {
            bpNew.x += bMove.x
        }
        if bp.y + bMove.y >= 0.0 + br && bp.y + bMove.y <= framebufferHeight - br {
            bpNew.y += bMove.y
        }
        
        return (ap + apNew, bp + bpNew)
    }
    
    private func collisionQuadtree(containerOfNodes: [[Int]], begin: Int, end: Int)
    {
        for k in begin ..< end {
            for i in 0 ..< containerOfNodes[k].count {
                for j in 1 + i ..< containerOfNodes[k].count {
                    
                    let ki = containerOfNodes[k][i]
                    let kj = containerOfNodes[k][j]
                    
                    if collisionCheck(ki, kj) {
                        
                        // Should the circles intersect. Seperate them. If not the next
                        // calculated values will be off.
                        (position[ki], position[kj]) = separate(ki, kj)
                        
                        (velocity[ki], velocity[kj]) = collisionResolve(ki, kj)
                    }
                }
            }
        }
    }
    
    private func collisionLogNxN(total: Int, begin: Int, end: Int)
    {
        for i in begin ..< end {
            for j in 1 + i ..< total {
                
                if collisionCheck(i, j) {
                    
                    // Should the circles intersect. Seperate them. If not the next
                    // calculated values will be off.
                    (position[i], position[j]) = separate(i, j)
                    
                    (velocity[i], velocity[j]) = collisionResolve(i, j)
                }
            }
        }
    }
    
    
    
    
    
    ////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////
    //////////  UTILITY
    ////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////
    
    
    
    public func addParticleWith(position: float2, color: float4, radius: Float)
    {
        self.id.append(particleCount)
        self.position.append(position)
        self.velocity.append(randFloat2(-5, 5))
        self.radius.append(radius)
        self.color.append(color)
        //        self.density.append(1)
        self.mass.append(Float.pi * radius * radius)
        
        self.particleCount += 1
        
        particleData.append(ParticleGPU(position: position, color: color, radius: radius))
    }
    
    public func getParticleDataForGPU() -> [ParticleGPU]
    {
        var result: [ParticleGPU] = []
        for i in 0 ..< particleCount {
            let pd = ParticleGPU.init(position: self.position[i], color: self.color[i], radius: self.radius[i])
            result.append(pd)
        }
        return result
    }
    
    /**
     Returns the minimum and maximum position found of all particles
     */
    public func getMinAndMaxPosition() -> (float2, float2)
    {
        var max = float2(Float((-INT_MAX)), Float(-INT_MAX))
        var min = float2(Float(INT_MAX), Float(INT_MAX))
        
        for i in 0 ..< particleCount {
            
            let pos = position[i]
            
            max.x = (pos.x > max.x) ? pos.x : max.x
            max.y = (pos.y > max.y) ? pos.y : max.y
            min.x = (pos.x < min.x) ? pos.x : min.x
            min.y = (pos.y < min.y) ? pos.y : min.y
        }
        
        return (min, max)
    }
    
    
    public func goTowardsPoint(_ point: float2, particleIDs: [Int])
    {
        for id in particleIDs {
            velocity[id] = gravityWell(particleID: id, point: point)
        }
    }
    
    public func gravityWell(particleID: Int, point: float2) -> float2
    {
        
        let v1 = velocity[particleID]
        let x1 = position[particleID].x
        let y1 = position[particleID].y
        let x2 = point.x
        let y2 = point.y
        let m1 = mass[particleID]
        let m2 = Float(1e11)
        
        let dx = x2 - x1
        let dy = y2 - y1
        let d = sqrt(dx * dx + dy * dy)
        
        let angle = atan2(dy, dx)
        let G = Float(kGravitationalConstant)
        let F = G * m1 * m2 / d * d
        
        let nX = F * cos(angle)
        let nY = F * sin(angle)
        
        return float2(v1.x + nX, v1.y + nY)
    }
    
    /**
     Returns an array of ids that fit inside the circle
     */
    public func getParticlesInCircle(position: float2, radius: Float) -> [Int] {
        var ids: [Int] = []
        
        // Brute-force
        for b in 0 ..< particleCount {
            
            let bID = id[b]
            
            if collisionCheck(bID, position: position, radius: radius) {
                ids.append(bID)
            }
        }
        
        return ids
    }
    
}
