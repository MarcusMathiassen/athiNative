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

private let randFuncString = """
    // Generate a random float in the range [0.0f, 1.0f] using x, y, and z (based on the xor128 algorithm)
    float rand(int x, int y, int z)
    {
        int seed = x + y * 57 + z * 241;
        seed= (seed<< 13) ^ seed;
        return (( 1.0 - ( (seed * (seed * seed * 15731 + 789221) + 1376312589) & 2147483647) / 1073741824.0f) + 1.0f) / 2.0f;
    }
"""

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
    \n
        {
            //----------------------------------
            //  attractedToMouse
            //----------------------------------
    
            // Local variables
            const auto pos = positions[index];
            const auto vel = velocities[index];
            const auto mass = masses[index];
    
            velocities[index] = attract_to_point(simParam.attractPoint, pos, vel, mass);
        }
    \n
    """

    case hasLifetime = """
    \n
    {
        //----------------------------------
        //  hasLifetime
        //----------------------------------

        // Respawn the particle if dead
        if (!isAlives[index] && !simParam.shouldAddParticle) {

    //            positions[index] = simParam.newParticlePosition;
    //            velocities[index] = simParam.newParticleVelocity;
    //            radii[index] = simParam.newParticleRadius;
    //            masses[index] = simParam.newParticleMass;
    //            colors[index] = simParam.newParticleColor;
    //
    //            isAlives[index] = true;
    //            lifetimes[index] = simParam.newParticleLifetime;

            return;
        }

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
    }
    \n
    """

    case update = """
    \n
    {
        //----------------------------------
        //  update
        //----------------------------------
    
        // The last thread is responsible for adding the new particle
        if (index == gpuParticleCount && simParam.shouldAddParticle) {
    
            // how many particles to add?
            const int amount =  simParam.particleCount - gpuParticleCount;
            gpuParticleCount = simParam.particleCount;
    
            // Each new particle gets the same position but different velocities
            for (int i = 0; i < amount; ++i) {
    
                const int newIndex = index+i;
                const float r = rand(newIndex, simParam.particleCount/3, 34);
    
                positions[newIndex] = simParam.newParticlePosition;
                velocities[newIndex] = simParam.newParticleVelocity * r;
                radii[newIndex] = simParam.newParticleRadius;
                masses[newIndex] = simParam.newParticleMass;
    
    #ifdef HAS_DRAW
                colors[newIndex] = simParam.newParticleColor;
    #endif
    
    #ifdef HAS_LIFETIME
                isAlives[newIndex] = true;
                lifetimes[newIndex] = simParam.newParticleLifetime;
    #endif
            }
        }

        velocities[index] += simParam.gravityForce;
        positions[index] += velocities[index];
    }
    \n
    """

    case draw = """
    \n
    {
        //----------------------------------
        //  draw
        //----------------------------------
        const float2 viewportSize = simParam.viewportSize;
        const float2 ppos = positions[index];
        if (ppos.x > 0 && ppos.x < viewportSize.x &&
            ppos.y > 0 && ppos.y < viewportSize.y) {

            const ushort2 fpos = ushort2(ppos.x, viewportSize.y - ppos.y);
            texture.write(colors[gid], fpos);
        }
    }
    \n
    """

    case borderBound = """
    \n
        {
            //----------------------------------
            //  borderBound
            //----------------------------------
    
    
            // Local variables
            auto pos = positions[index];
            auto vel = velocities[index];
            const auto radi = radii[index];
            const auto viewportSize = simParam.viewportSize;
    
            if (pos.x < 0 + radi)               { pos.x = 0 + radi;                 vel.x = -vel.x; }
            if (pos.x > viewportSize.x - radi)  { pos.x = viewportSize.x - radi;    vel.x = -vel.x; }
            if (pos.y < 0 + radi)               { pos.y = 0 + radi;                 vel.y = -vel.y; }
            if (pos.y > viewportSize.y - radi)  { pos.y = viewportSize.y - radi;    vel.y = -vel.y; }
    
            positions[index] = pos;
            velocities[index] = vel;
        }
    \n
    """

    case interCollision = """
    \n
    {
        //----------------------------------
        //  interCollision
        //----------------------------------
    
        // Local variables
        auto pos = positions[index];
        auto vel = velocities[index];
        const auto radi = radii[index];
        const auto mass = masses[index];

        for (uint otherIndex = 0; otherIndex < simParam.particleCount; ++otherIndex) {

    #ifdef HAS_LIFETIME
            if (!isAlives[otherIndex]) continue;
    #endif

            if (index == otherIndex) continue;

            const float2 other_pos = positions[otherIndex];
            const float other_radi = radii[otherIndex];

            if (collision_check(pos, other_pos, radi, other_radi)) {

                const float2 other_vel = velocities[otherIndex];
                const float other_mass = masses[otherIndex];

                vel = collision_resolve(pos, vel, mass, other_pos, other_vel, other_mass);
            }
        }
        positions[index] = pos;
        velocities[index] = vel;
    }
    \n
    """
}

final class ParticleSystem {

    var options: [ParticleOption] = [.update]
    var computeDeviceOption: ComputeDeviceOption = .cpu

    public var particleCount: Int = 0 // Amount of particles
    var maxParticles: Int

    var simParam: SimParam = SimParam()

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
    private var dynamicBufferResourceOption: MTLResourceOptions = .storageModePrivate
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
    
    private var gpuParticleCountBuffer: MTLBuffer

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
            vector_float2 viewportSize;
            vector_float2 attractPoint;
            vector_float2 gravityForce;

            vector_float2 mousePos;
            float currentTime;

            uint particleCount;
            bool shouldAddParticle;
            vector_float2 newParticlePosition;
            vector_float2 newParticleVelocity;
            float newParticleRadius;
            float newParticleMass;
            vector_float4 newParticleColor;
            float newParticleLifetime;
        } SimParam;
        """

        for option in options {
            switch option {
            case .update:
                rawKernelString += "\n#define HAS_UPDATE\n"
            case .hasLifetime:
                rawKernelString += "\n#define HAS_LIFETIME\n"
            case .interCollision:
                rawKernelString += "\n#define HAS_INTERCOLLISION\n"
            case .attractedToMouse: break
            case .draw:
                rawKernelString += "\n#define HAS_DRAW\n"
            case .borderBound:
                rawKernelString += "\n#define HAS_BORDERBOUND\n"
            }
        }


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
                         texture2d<float, access::write>    texture                   [[texture(0)]],
                         device bool*       isAlives    [[buffer(5)]],
                         device float*      lifetimes   [[buffer(6)]],

                         device uint&                       gpuParticleCount          [[buffer(7)]],
                         constant MotionParam&              motionParam               [[buffer(8)]],
                         constant SimParam&                 simParam                  [[buffer(9)]],
                         uint                               gid                       [[thread_position_in_grid]])
        {

            // Local variables
            const uint index = gid;
        """

        for option in options {
            rawKernelString += option.rawValue
        }

        rawKernelString += "}\n"
    }

    init(device: MTLDevice,
         options: [ParticleOption] = [.update, .draw],
         maxParticles: Int = 100_000) {

        self.maxParticles = maxParticles
        self.options = options

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

        // Initalize our GPU buffers
        positionsBuffer = device.makeBuffer(
            length: MemoryLayout<float2>.stride * maxParticles,
            options: dynamicBufferResourceOption)!
        velocitiesBuffer = device.makeBuffer(
            length: MemoryLayout<float2>.stride * maxParticles,
            options: dynamicBufferResourceOption)!
        radiiBuffer = device.makeBuffer(
            length: MemoryLayout<Float>.stride * maxParticles,
            options: dynamicBufferResourceOption)!
        massesBuffer = device.makeBuffer(
            length: MemoryLayout<Float>.stride * maxParticles,
            options: dynamicBufferResourceOption)!
        colorsBuffer = device.makeBuffer(
            length: MemoryLayout<float4>.stride * maxParticles,
            options: dynamicBufferResourceOption)!
        isAlivesBuffer = device.makeBuffer(
            length: MemoryLayout<Bool>.stride * maxParticles,
            options: dynamicBufferResourceOption)!
        lifetimesBuffer = device.makeBuffer(
            length: MemoryLayout<Float>.stride * maxParticles,
            options: dynamicBufferResourceOption)!
        
        var val: UInt32 = 0
        gpuParticleCountBuffer = device.makeBuffer(
            bytes: &val,
            length: MemoryLayout<UInt32>.stride,
            options: .storageModeShared)!

        particlesAllocatedCount = maxParticles

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

        computeHelperFunctions.append(randFuncString)

        if options.contains(.attractedToMouse) {
            computeHelperFunctions.append(attractToPointFuncString)
        }

        if options.contains(.interCollision) {
             computeHelperFunctions.append(collisionCheckFuncString)
             computeHelperFunctions.append(collisionResolveFuncString)
        }

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

    private func updateParticles(commandBuffer: MTLCommandBuffer) {

        commandBuffer.pushDebugGroup("Particles Update")

        let computeEncoder = commandBuffer.makeComputeCommandEncoder()

        computeEncoder?.setComputePipelineState(computePipelineState!)

        computeEncoder?.setBuffer(positionsBuffer, offset: 0, index: 0)
        computeEncoder?.setBuffer(velocitiesBuffer, offset: 0, index: 1)
        computeEncoder?.setBuffer(gpuParticleCountBuffer, offset: 0, index: 7)


        if options.contains(.interCollision) || options.contains(.hasLifetime) {
            computeEncoder?.setBuffer(radiiBuffer, offset: 0, index: 2)
            computeEncoder?.setBuffer(massesBuffer, offset: 0, index: 3)
        }

        if options.contains(.draw) {
            computeEncoder?.setBuffer(colorsBuffer, offset: 0, index: 4)
            computeEncoder?.setTexture(pTexture, index: 0)
        }

        if options.contains(.hasLifetime) {
            computeEncoder?.setBuffer(isAlivesBuffer, offset: 0, index: 5)
            computeEncoder?.setBuffer(lifetimesBuffer, offset: 0, index: 6)
        }

        var motionParam = MotionParam()
        motionParam.deltaTime = 1/60
        computeEncoder?.setBytes(&motionParam,
                                 length: MemoryLayout<MotionParam>.stride,
                                 index: 8)

        simParam.particleCount = uint(particleCount)
        simParam.viewportSize = viewportSize
        simParam.attractPoint = mousePos
        simParam.mousePos = mousePos
        simParam.currentTime = Float(getTime())
        simParam.gravityForce = enableGravity ? float2(0, gravityForce) : float2(0)
        computeEncoder?.setBytes(&simParam, length: MemoryLayout<SimParam>.stride, index: 9)

        // Reset simParams
        simParam.shouldAddParticle = false
        simParam.newParticlePosition = mousePos


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
            self.bufferSemaphore.signal()
        }
    }

    public func eraseParticles() {
        self.particleCount = 0
    }

    public func addParticleWith(position: float2, color: float4, radius: Float) {

        if self.particleCount == self.maxParticles { return }

        self.particleCount += 1

        self.simParam.shouldAddParticle = true
        self.simParam.newParticlePosition = position
        self.simParam.newParticleVelocity = hasInitialVelocity ? randFloat2(-5, 5) : float2(0)
        self.simParam.newParticleRadius = radius
        self.simParam.newParticleMass = Float.pi * radius * radius * radius
        self.simParam.newParticleColor = color
        self.simParam.newParticleLifetime = 1.0
    }
}
