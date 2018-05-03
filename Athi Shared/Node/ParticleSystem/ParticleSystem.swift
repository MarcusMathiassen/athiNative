//
//  ParticleSystem.swift
//  Athi
//
//  Created by Marcus Mathiassen on 04/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

import Metal
import MetalKit
import MetalPerformanceShaders

private let attractToPointFuncString = """
float2 attract_to_point(float2 point, float2 p1, float2 v1, float m1)
{
    const auto dp = point - p1;
    const float d = sqrt(dp.x * dp.x + dp.y * dp.y);

    const float angle = atan2(dp.y, dp.x);

    float2 new_vel = v1;

    new_vel.x += d * cos(angle) * 0.001;
    new_vel.y += d * sin(angle) * 0.001;

    return new_vel;
}
"""

private let collisionCheckFuncString = """
bool collision_check(float2 ap, float2 bp, float ar, float br)
{
    const float ax = ap.x;
    const float ay = ap.y;
    const float bx = bp.x;
    const float by = bp.y;

    // square collision check
    if (ax - ar < bx + br && ax + ar > bx - br && ay - ar < by + br &&
    ay + ar > by - br) {
        // Particle collision check
        const float dx = bx - ax;
        const float dy = by - ay;

        const float sum_radius = ar + br;
        const float sqr_radius = sum_radius * sum_radius;

        const float distance_sqr = (dx * dx) + (dy * dy);

        if (distance_sqr <= sqr_radius) return true;
    }

    return false;
}
"""

private let collisionResolveFuncString = """
float2 collision_resolve(float2 p1, float2 v1, float m1, float2 p2, float2 v2, float m2)
{
    // local variables
    const float2 dp = p2 - p1;
    const float2 dv = v2 - v1;
    const float d = dp.x * dv.x + dp.y * dv.y;

    // We skip any two particles moving away from eachother
    if (d < 0) {
        const float2 norm = normalize(dp);
        const float2 tang = float2(norm.y * -1.0f, norm.x);

        const float scal_norm_1 = dot(norm, v1);
        const float scal_norm_2 = dot(norm, v2);
        const float scal_tang_1 = dot(tang, v1);
        const float scal_norm_1_after = (scal_norm_1 * (m1 - m2) + 2.0f * m2 * scal_norm_2) / (m1 + m2);
        const float2 scal_norm_1_after_vec = norm * scal_norm_1_after;
        const float2 scal_norm_1_vec = tang * scal_tang_1;

        return (scal_norm_1_vec + scal_norm_1_after_vec) * 0.98;
    }
    return v1;
}
"""

enum ParticleOption: String {

    case attractedToMouse = """

        //----------------------------------
        //  attractedToMouse
        //----------------------------------
        vel = attract_to_point(simParam.attract_point, pos, vel, mass);

    """

    case hasLifetime = """

        //----------------------------------
        //  hasLifetime
        //----------------------------------

        // We exit immidiatly if the particle is dead
        if (!isAlives[index]) return;
    
        // Local variables
        bool isAlive = isAlives[index];
        float lifetime = lifetimes[index];

        // Decrease the lifetime
        lifetime -= motionParam.deltaTime;

        // If the lifetime of this particle has come to an end. Dont update it, dont draw it.
        if (lifetime <= 0) isAlive = false;

        // Fade the particle out until it's dead
        colors[index] = float4(colors[index].rgb, lifetime);

        // Update
        lifetimes[index] = lifetime;
        isAlives[index] = isAlive;
    """

    case update = """

        //----------------------------------
        //  update
        //----------------------------------

        velocities[index] = vel + gravity_force;
        positions[index] = pos + vel;
        radii[index] = radi;
        masses[index] = mass;
    """

    case draw = """

        //----------------------------------
        //  draw
        //----------------------------------

        const float2 ppos = positions[index];
        if (ppos.x > 0 && ppos.x < viewportSize.x &&
            ppos.y > 0 && ppos.y < viewportSize.y) {

            const ushort2 fpos = ushort2(ppos.x, viewportSize.y - ppos.y);
            texture.write(colors[gid], fpos);
        }

    """

    case borderBound = """

        //----------------------------------
        //  borderBound
        //----------------------------------

        if (pos.x < 0 + radi)               { pos.x = 0 + radi;                 vel.x = -vel.x; }
        if (pos.x > viewportSize.x - radi)  { pos.x = viewportSize.x - radi;    vel.x = -vel.x; }
        if (pos.y < 0 + radi)               { pos.y = 0 + radi;                 vel.y = -vel.y; }
        if (pos.y > viewportSize.y - radi)  { pos.y = viewportSize.y - radi;    vel.y = -vel.y; }

    """

    case interCollision = """

        //----------------------------------
        //  interCollision
        //----------------------------------

        for (uint otherIndex = 0; otherIndex < particleCount; ++otherIndex) {

            if (index == otherIndex) continue;

            const float2 other_pos = positions[otherIndex];
            const float other_radi = radii[otherIndex];

            if (collision_check(pos, other_pos, radi, other_radi)) {

                const float2 other_vel = velocities[otherIndex];
                const float other_mass = masses[otherIndex];

                vel = collision_resolve(pos, vel, mass, other_pos, other_vel, other_mass);
            }
        }

    """
}

final class ParticleSystem {

    var maxParticles: Int
    private var particles: [Particle] = []
    var options: [ParticleOption] = [.update]
    var computeDeviceOption: ComputeDeviceOption = .cpu

    public var particleCount: Int = 0 // Amount of particles
    
    //----------------------------------
    //  Particle data
    //----------------------------------
    var positions: [float2] = []
    var velocities: [float2] = []
    var radii: [Float] = []
    var masses: [Float] = []
    var isAlives: [Bool] = []
    var lifetimes: [Float] = []
    var colors: [float4] = []

    // Options
    var shouldRepel: Bool = false
    var enableMultithreading: Bool = false
    var enableBorderCollision: Bool = true
    var collisionEnergyLoss: Float = 0.98
    var gravityForce: Float = -0.0981
    var enableGravity: Bool = false
    var enableCollisions: Bool = false
    var useAccelerometerAsGravity: Bool = false
    var useQuadtree: Bool = true
    var hasInitialVelocity: Bool = true

    var isPaused: Bool = false

    private var tempGravityForce = float2(0)
    private var shouldUpdate: Bool = false

    ///////////////////
    // Rendering
    ///////////////////

    // Static data uploaded once, and updated when numVerticesPerParticle is changed
    // Metal stuff

    // Rendering stuff

    var enablePostProcessing: Bool = true
    var postProcessingSamples: Int = 1
    var blurStrength: Float = 10
    var preAllocatedParticles = 1
    private var particlesAllocatedCount: Int = 0
    #if os(macOS)
    private var dynamicBufferResourceOption: MTLResourceOptions = .storageModeShared
    private var staticBufferResourceOption: MTLResourceOptions = .storageModeShared
    #else
    private var dynamicBufferResourceOption: MTLResourceOptions = .cpuCacheModeWriteCombined
    private var staticBufferResourceOption: MTLResourceOptions = .storageModeShared
    #endif
    var particleColor = float4(1)
    var numVerticesPerParticle = 36
    private var quad: Quad
    private var device: MTLDevice
    
    
    // GPU Buffers
    private var positionsBuffer: MTLBuffer
    private var velocitiesBuffer: MTLBuffer
    private var radiiBuffer: MTLBuffer
    private var massesBuffer: MTLBuffer
    private var colorsBuffer: MTLBuffer
    private var isAlivesBuffer: MTLBuffer
    private var lifetimesBuffer: MTLBuffer

    private var pipelineState: MTLRenderPipelineState?
    private var computePipelineState: MTLComputePipelineState?

    var inTexture: MTLTexture
    var outTexture: MTLTexture
    var finalTexture: MTLTexture

    var pTexture: MTLTexture

    var bufferSemaphore = DispatchSemaphore(value: 1)

    var computeHelperFunctions: [String] = []
    var rawKernelString: String = ""

    func setOptions(_ options: [ParticleOption], helperFunctions: [String]) {

        rawKernelString = """
        #include <metal_stdlib>
        using namespace metal;

        typedef struct
        {
            float           deltaTime;       // frame delta time
        } MotionParam;

        typedef struct
        {
            vector_float2 viewport_size;
            vector_float2 attract_point;
            vector_float2 gravity_force;
        
            vector_float2 mouse_pos;
            float current_time;
        
            bool shouldAddParticle;
            vector_float2 newParticlePosition;
            vector_float2 newParticleVelocity;
            float newParticleRadius;
            float newParticleMass;
        } SimParam;
        """

        for function in helperFunctions {
            rawKernelString += function
        }

        rawKernelString += """

        kernel
        void big_compute(
                         device float2*     positions   [[buffer(0)]],
                         device float2*     velocities  [[buffer(1)]],
                         device float*      radii       [[buffer(2)]],
                         device float*      masses      [[buffer(3)]],
                         device float4*     colors      [[buffer(4)]],
                         device bool*       isAlives    [[buffer(5)]],
                         device float*      lifetimes   [[buffer(6)]],
        
                         constant uint&                     particleCount             [[buffer(7)]],
                         constant MotionParam&              motionParam               [[buffer(8)]],
                         constant SimParam&                 simParam                  [[buffer(9)]],
                         texture2d<float, access::write>    texture                   [[texture(0)]],

                         uint                               gid                       [[thread_position_in_grid]])
        {

            // Local variables
            const uint index = gid;
            float2 pos = positions[index];
            float2 vel = velocities[index];
            float radi = radii[index];
            float mass = masses[index];

            const float2 viewportSize = simParam.viewport_size;
            const float2 gravity_force = simParam.gravity_force;
        """

        for option in options {
            rawKernelString += option.rawValue
        }

        rawKernelString += "}\n"
    }

    init(device: MTLDevice,
         options: [ParticleOption] = [.update, .draw],
         maxParticles: Int = 10_000) {
        
        self.maxParticles = maxParticles

        self.device = device
        quad = Quad(device: device)

        let library = device.makeDefaultLibrary()!
        let vertexFunc = library.makeFunction(name: "particle_vert")!
        let fragFunc = library.makeFunction(name: "particle_frag")!

        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.label = "pipelineDesc"
        pipelineDesc.vertexFunction = vertexFunc
        pipelineDesc.fragmentFunction = fragFunc
        pipelineDesc.colorAttachments[0].pixelFormat = Renderer.pixelFormat
        pipelineDesc.colorAttachments[1].pixelFormat = Renderer.pixelFormat

        do {
            try pipelineState = device.makeRenderPipelineState(
            descriptor: pipelineDesc)
        } catch {
            print("ParticleSystem Pipeline: Creating pipeline state failed")
        }
        
        
        // Initalize our CPU buffers
//        positions       = [float2](repeating: float2(0), count: maxParticles)
//        velocities      = [float2](repeating: float2(0), count: maxParticles)
//        radii           = [Float](repeating: 0, count: maxParticles)
//        masses          = [Float](repeating: 0, count: maxParticles)
//        colors          = [float4](repeating: float4(1), count: maxParticles)
//        isAlives        = [Bool](repeating: true, count: maxParticles)
//        lifetimes       = [Float](repeating: 1.0, count: maxParticles)
//
        // Initalize our GPU buffers
        positionsBuffer = device.makeBuffer(
            bytes: &positions,
            length: MemoryLayout<float2>.stride * maxParticles,
            options: dynamicBufferResourceOption)!
        velocitiesBuffer = device.makeBuffer(
            bytes: &velocities,
            length: MemoryLayout<float2>.stride * maxParticles,
            options: dynamicBufferResourceOption)!
        radiiBuffer = device.makeBuffer(
            bytes: &radii,
            length: MemoryLayout<Float>.stride * maxParticles,
            options: dynamicBufferResourceOption)!
        massesBuffer = device.makeBuffer(
            bytes: &masses,
            length: MemoryLayout<Float>.stride * maxParticles,
            options: dynamicBufferResourceOption)!
        colorsBuffer = device.makeBuffer(
            bytes: &colors,
            length: MemoryLayout<float4>.stride * maxParticles,
            options: dynamicBufferResourceOption)!
        isAlivesBuffer = device.makeBuffer(
            bytes: &isAlives,
            length: MemoryLayout<Bool>.stride * maxParticles,
            options: dynamicBufferResourceOption)!
        lifetimesBuffer = device.makeBuffer(
            bytes: &lifetimes,
            length: MemoryLayout<Float>.stride * maxParticles,
            options: dynamicBufferResourceOption)!
        
//        particleCount = maxParticles
        
        let textureDesc = MTLTextureDescriptor()
        textureDesc.height = Int(framebufferHeight)
        textureDesc.width = Int(framebufferWidth)
        textureDesc.sampleCount = 1
        textureDesc.textureType = .type2D
        textureDesc.pixelFormat = Renderer.pixelFormat
        textureDesc.resourceOptions = .storageModePrivate
        textureDesc.usage = .shaderRead
        inTexture = device.makeTexture(descriptor: textureDesc)!

        textureDesc.usage = .shaderWrite
        outTexture = device.makeTexture(descriptor: textureDesc)!

        pTexture = device.makeTexture(descriptor: textureDesc)!
        finalTexture = device.makeTexture(descriptor: textureDesc)!

        computeHelperFunctions.append(contentsOf:
            [
                collisionCheckFuncString,
                collisionResolveFuncString,
                attractToPointFuncString
            ]
        )

        setOptions(options, helperFunctions: computeHelperFunctions)

        do {
            let compOp = MTLCompileOptions()
            compOp.fastMathEnabled = true
            compOp.languageVersion = .version2_0

            print(rawKernelString)
            let libraryC = try device.makeLibrary(source: rawKernelString, options: compOp)
            let computeFunc = libraryC.makeFunction(name: "big_compute")

            try computePipelineState = device.makeComputePipelineState(function: computeFunc!)

        } catch {
            print("Cant compile ParticleSystem options", error.localizedDescription)
            exit(0)
        }
    }

    public func draw(
        view: MTKView,
        frameDescriptor: FrameDescriptor,
        commandBuffer: MTLCommandBuffer
        ) {

        if particleCount == 0 { return }

        commandBuffer.pushDebugGroup("ParticleSystem Draw")

        let renderPassDesc = MTLRenderPassDescriptor()
        renderPassDesc.colorAttachments[0].clearColor = frameDescriptor.clearColor
        renderPassDesc.colorAttachments[0].texture = inTexture
        renderPassDesc.colorAttachments[0].loadAction = .clear
        renderPassDesc.colorAttachments[0].storeAction = .store

        renderPassDesc.colorAttachments[1].clearColor = frameDescriptor.clearColor
        renderPassDesc.colorAttachments[1].texture = finalTexture
        renderPassDesc.colorAttachments[1].loadAction = .clear
        renderPassDesc.colorAttachments[1].storeAction = .store

        var renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc)!

        renderEncoder.pushDebugGroup("Draw particles (off-screen)")
        renderEncoder.setRenderPipelineState(pipelineState!)

        quad.draw(renderEncoder: renderEncoder, texture: pTexture)

        renderEncoder.popDebugGroup()
        renderEncoder.endEncoding()

        if enablePostProcessing {

            renderEncoder.pushDebugGroup("Apply Post Processing")

            let blurKernel = MPSImageGaussianBlur(device: device, sigma: blurStrength)

            blurKernel.encode(
                commandBuffer: commandBuffer,
                sourceTexture: inTexture,
                destinationTexture: outTexture
                )

            quad.mix(
                commandBuffer: commandBuffer,
                inputTexture1: inTexture,
                inputTexture2: outTexture,
                outTexture: finalTexture,
                sigma: 5.0
                )

            renderEncoder.popDebugGroup()
        } else {
            quad.mix(
                commandBuffer: commandBuffer,
                inputTexture1: inTexture,
                inputTexture2: outTexture,
                outTexture: finalTexture,
                sigma: 5.0
            )
        }

        let viewRenderPassDesc = view.currentRenderPassDescriptor

        if viewRenderPassDesc != nil {

            viewRenderPassDesc?.colorAttachments[1].clearColor = frameDescriptor.clearColor
            viewRenderPassDesc?.colorAttachments[1].texture = pTexture
            viewRenderPassDesc?.colorAttachments[1].loadAction = .clear
            viewRenderPassDesc?.colorAttachments[1].storeAction = .store

            renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: viewRenderPassDesc!)!

            renderEncoder.pushDebugGroup("Draw particles (on-screen)")

            quad.draw(renderEncoder: renderEncoder, texture: finalTexture)

            renderEncoder.popDebugGroup()
            renderEncoder.endEncoding()

            commandBuffer.popDebugGroup()
        }
    }

    public func drawDebug(
        color: float4,
        view: MTKView,
        frameDescriptor: FrameDescriptor,
        commandBuffer: MTLCommandBuffer
        ) {
    }

    public func update(commandBuffer: MTLCommandBuffer) {

        if isPaused { return }

        if shouldUpdate {
            shouldUpdate = false
        }
        
        updateParticles(commandBuffer: commandBuffer)
    }

    private func updateGPUBuffers(commandBuffer: MTLCommandBuffer) {
        
        // Reallocate more if needed
        if particleCount > particlesAllocatedCount {
            
            // We need exclusive access to the buffer to make sure our copy is safe and correct
            _ = self.bufferSemaphore.wait(timeout: DispatchTime.distantFuture)
            
            memcpy(&self.positions, self.positionsBuffer.contents(), self.particlesAllocatedCount * MemoryLayout<float2>.stride)
            memcpy(&self.velocities, self.velocitiesBuffer.contents(), self.particlesAllocatedCount * MemoryLayout<float2>.stride)
            memcpy(&self.radii, self.radiiBuffer.contents(), self.particlesAllocatedCount * MemoryLayout<Float>.stride)
            memcpy(&self.masses, self.massesBuffer.contents(), self.particlesAllocatedCount * MemoryLayout<Float>.stride)
            memcpy(&self.colors, self.colorsBuffer.contents(), self.particlesAllocatedCount * MemoryLayout<float4>.stride)
            memcpy(&self.isAlives, self.isAlivesBuffer.contents(), self.particlesAllocatedCount * MemoryLayout<Bool>.stride)
            memcpy(&self.lifetimes, self.lifetimesBuffer.contents(), self.particlesAllocatedCount * MemoryLayout<Float>.stride)
            
            // Update the allocated particle count
            particlesAllocatedCount = particleCount

            positionsBuffer = device.makeBuffer(
                length: particlesAllocatedCount * MemoryLayout<float2>.stride,
                options: dynamicBufferResourceOption)!
            
            velocitiesBuffer = device.makeBuffer(
                length: particlesAllocatedCount * MemoryLayout<float2>.stride,
                options: dynamicBufferResourceOption)!
            
            radiiBuffer = device.makeBuffer(
                length: particlesAllocatedCount * MemoryLayout<Float>.stride,
                options: dynamicBufferResourceOption)!
            
            massesBuffer = device.makeBuffer(
                length: particlesAllocatedCount * MemoryLayout<Float>.stride,
                options: dynamicBufferResourceOption)!
            
            colorsBuffer = device.makeBuffer(
                length: particlesAllocatedCount * MemoryLayout<float4>.stride,
                options: dynamicBufferResourceOption)!

            isAlivesBuffer = device.makeBuffer(
                length: particlesAllocatedCount * MemoryLayout<Bool>.stride,
                options: dynamicBufferResourceOption)!

            lifetimesBuffer = device.makeBuffer(
                length: particlesAllocatedCount * MemoryLayout<Float>.stride,
                options: dynamicBufferResourceOption)!
            
            

            positionsBuffer.contents().copyMemory(
                from: &positions,
                byteCount: particlesAllocatedCount * MemoryLayout<float2>.stride)
            
            velocitiesBuffer.contents().copyMemory(
                from: &velocities,
                byteCount: particlesAllocatedCount * MemoryLayout<float2>.stride)
            
            radiiBuffer.contents().copyMemory(
                from: &radii,
                byteCount: particlesAllocatedCount * MemoryLayout<Float>.stride)
            
            massesBuffer.contents().copyMemory(
                from: &masses,
                byteCount: particlesAllocatedCount * MemoryLayout<Float>.stride)
            
            colorsBuffer.contents().copyMemory(
                from: &colors,
                byteCount: particlesAllocatedCount * MemoryLayout<float4>.stride)
            
            isAlivesBuffer.contents().copyMemory(
                from: &isAlives,
                byteCount: particlesAllocatedCount * MemoryLayout<Bool>.stride)
            
            lifetimesBuffer.contents().copyMemory(
                from: &lifetimes,
                byteCount: particlesAllocatedCount * MemoryLayout<Float>.stride)
        }
    }

    private func updateParticles(commandBuffer: MTLCommandBuffer) {

        commandBuffer.pushDebugGroup("Particles Update")

        let computeEncoder = commandBuffer.makeComputeCommandEncoder()

        computeEncoder?.setComputePipelineState(computePipelineState!)

        // Make sure to update the buffers before computing
        updateGPUBuffers(commandBuffer: commandBuffer)
        
        computeEncoder?.setBuffer(positionsBuffer,  offset: 0, index: 0)
        computeEncoder?.setBuffer(velocitiesBuffer, offset: 0, index: 1)
        computeEncoder?.setBuffer(radiiBuffer,      offset: 0, index: 2)
        computeEncoder?.setBuffer(massesBuffer,     offset: 0, index: 3)
        computeEncoder?.setBuffer(colorsBuffer,     offset: 0, index: 4)
        computeEncoder?.setBuffer(isAlivesBuffer,   offset: 0, index: 5)
        computeEncoder?.setBuffer(lifetimesBuffer,  offset: 0, index: 6)
        
        computeEncoder?.setBytes(&particleCount,
                                 length: MemoryLayout<UInt32>.stride,
                                 index: 7)

        computeEncoder?.setTexture(pTexture, index: 0)

        var motionParam = MotionParam()
        motionParam.deltaTime = 1/60
        computeEncoder?.setBytes(&motionParam,
                                 length: MemoryLayout<MotionParam>.stride,
                                 index: 8)

        var simParam = SimParam()
        simParam.viewport_size = viewportSize
        simParam.attract_point = mousePos
        simParam.mouse_pos = mousePos
        simParam.shouldAddParticle = false
        simParam.current_time = Float(getTime())
        simParam.gravity_force = enableGravity ? float2(0, gravityForce) : float2(0)
        computeEncoder?.setBytes(&simParam,
                                 length: MemoryLayout<SimParam>.stride,
                                 index: 9)

        // Compute kernel threadgroup size
        let threadExecutionWidth = (computePipelineState?.threadExecutionWidth)!

        // A one dimensional thread group Swift to pass Metal a one dimensional array
        let threadGroupCount = MTLSize(
            width: threadExecutionWidth,
            height: 1,
            depth: 1)

        let recommendedThreadGroupWidth = (particleCount + threadGroupCount.width - 1) / threadGroupCount.width

        let threadGroups = MTLSize(
            width: recommendedThreadGroupWidth,
            height: 1,
            depth: 1)

        computeEncoder?.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCount)

        // Finish
        computeEncoder?.endEncoding()
        commandBuffer.popDebugGroup()

        commandBuffer.addCompletedHandler { (_) in
//
//            memcpy(&self.particles, self.particlesBuffer.contents(), self.particlesAllocatedCount * MemoryLayout<Particle>.stride)

            self.bufferSemaphore.signal()
        }
    }

    /**
        Remove all the particles.
    */
    public func eraseParticles() {

        particles.removeAll()
        velocities.removeAll()
        radii.removeAll()
        masses.removeAll()
        colors.removeAll()
        isAlives.removeAll()
        lifetimes.removeAll()

        particlesAllocatedCount = 0

        particleCount = 0
    }

    public func addParticleWith(position: float2, color: float4, radius: Float) {

        var vel = float2(0)
        if hasInitialVelocity {
            vel = (randFloat2(-5, 5))
        }

        self.positions.append(position)
        self.velocities.append(vel)
        self.radii.append(radius)
        self.colors.append(color)
        self.masses.append(Float.pi * radius * radius * radius)
        self.isAlives.append(true)
        self.lifetimes.append(1.0)

        self.particleCount += 1
    }
}
