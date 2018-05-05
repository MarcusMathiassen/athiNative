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

    float2 rand2(float min, float max, int x, int y, int z)
    {
        const float inputX = rand(x,y,z);
        const float inputY = rand(z,x,y);

        // Map to range
        const float slope = 1.0 * (max - min);
        const float xr = min + slope * (inputX);
        const float yr = min + slope * (inputY);

        return float2(xr, yr);
    }
"""

private let attractToPointFuncString = """
    float2 attract_to_point(float2 point, float2 p1, float2 v1, float m1)
    {
        return normalize(point - p1) + v1;
    }

    float2 homingMissile(float2 target,
                         float strength,
                         float2 p1,
                         float2 v1
    ){
        return strength * normalize(target - p1) + v1;
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
    
    case variableSize = ""
    
    case isHoming = """
    \n
        {
            //----------------------------------
            //  isHoming
            //----------------------------------
    
            // Local variables
            const auto pos = positions[index];
            const auto vel = velocities[index];
    
            velocities[index] = homingMissile(simParam.attractPoint, 1.0, pos, vel);
    
        }
    \n
    """
    
    case turbulence = """
    \n
        {
            //----------------------------------
            //  turbulence
            //----------------------------------
    
            
        }
    \n
    """
    
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
    
            velocities[index] = attract_to_point(simParam.mousePos, pos, vel, mass);
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
    
                const float2 randVel = rand2(simParam.newParticleVelocity.x, simParam.newParticleVelocity.y, index, simParam.particleCount/3, 34);
    
                positions[index] = simParam.newParticlePosition;
                velocities[index] = randVel;
                isAlives[index] = true;
                lifetimes[index] = simParam.newParticleLifetime;
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
            gpuParticleCount += amount;
    
            const float2 initalVelocity = simParam.newParticleVelocity;
    
            // Each new particle gets the same position but different velocities
            for (int i = 0; i < amount; ++i) {
    
                const int newIndex = index+i;
    
                const float2 randVel = rand2(initalVelocity.x, initalVelocity.y, newIndex, simParam.particleCount/3, 34);
    
                positions[newIndex] = simParam.newParticlePosition;
                velocities[newIndex] = randVel;
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
    
        // Update
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


enum MissileOptions {
    case homing
}

enum EmitterOptions {
    case hasInterCollision
    case isBorderBound
    case createWithMouse
    case hasLifetime
}

/**
 Emmits particles.
 */
struct Emitter {
    
    /**
     The position to spawn from.
    */
    var spawnPoint: float2 = float2(0)
    
    /**
     The Emmit direction. Normalized.
    */
    var spawnDirection: float2 = float2(0)
    
    /**
     The initial velocity of each particle emmited
     */
    var spawnSpeed: Float = 0
    
    /**
     The amount of particles this emitter emmits.
    */
    private var particleCount: Int = 0
    
    /**
     The maximum amount of particles this emitter can emmit.
    */
    var maxParticleCount: Int = 0
    
    var options: [EmitterOptions] = []
    var missleOptions: [MissileOptions] = []
}

final class ParticleSystem {
    
    // Each emitter gets a piece of the total particleCount to use.
    var emitters: [Emitter] = []
    var maxParticles: Int
    
    var options: [ParticleOption] = [.update]
    var computeDeviceOption: ComputeDeviceOption = .cpu

    public var particleCount: Int = 0 // Amount of particles

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
    var attractPoint = float2(0)
    private var quad: Quad
    private var device: MTLDevice

    // Buffers are shared between all Emitters in a ParticleSystem.
    //  Their size never changes, and must be set at compile time.
    private var positionsBuffer: MTLBuffer
    private var velocitiesBuffer: MTLBuffer
    private var radiiBuffer: MTLBuffer
    private var massesBuffer: MTLBuffer
    private var colorsBuffer: MTLBuffer
    private var isAlivesBuffer: MTLBuffer
    private var lifetimesBuffer: MTLBuffer
    
    private var vertices: [float2] = []
    private var indices: [UInt16] = []
    
    private var vertexBuffer: MTLBuffer
    private var indexBuffer: MTLBuffer
    
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
            bool clearParticles;
            float initialVelocity;
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
            case .attractedToMouse:
                rawKernelString += "\n#define HAS_ATTRACTED_TO_MOUSE\n"
            case .draw:
                rawKernelString += "\n#define HAS_DRAW\n"
            case .borderBound:
                rawKernelString += "\n#define HAS_BORDERBOUND\n"
            case .turbulence:
                break
            case .variableSize:
                break
            case .isHoming:
                break
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
        
        
        
            // If the particles have been cleared or deleted
            if (simParam.clearParticles) {
                gpuParticleCount = simParam.particleCount;
            }

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
        do {
            let constVals = MTLFunctionConstantValues()
            var has_lifetime = options.contains(.hasLifetime)
            constVals.setConstantValue(&has_lifetime, type: MTLDataType.bool, withName: "has_lifetime")
            let vertexFunc = try library.makeFunction(name: "particle_vert", constantValues: constVals)
            let fragFunc = library.makeFunction(name: "particle_frag")!
            
            let pipelineDesc = MTLRenderPipelineDescriptor()
            pipelineDesc.label = "pipelineDesc"
            pipelineDesc.vertexFunction = vertexFunc
            pipelineDesc.fragmentFunction = fragFunc
            pipelineDesc.colorAttachments[0].pixelFormat = Renderer.pixelFormat
            pipelineDesc.colorAttachments[1].pixelFormat = Renderer.pixelFormat
            
            pipelineDesc.colorAttachments[0].isBlendingEnabled = true
            pipelineDesc.colorAttachments[0].rgbBlendOperation = .add
            pipelineDesc.colorAttachments[0].alphaBlendOperation = .add
            pipelineDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            pipelineDesc.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
            pipelineDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            pipelineDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            
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
        
        gpuParticleCountBuffer = device.makeBuffer(
            length: MemoryLayout<UInt32>.stride,
            options: dynamicBufferResourceOption)!

        particlesAllocatedCount = maxParticles
        
        vertexBuffer = device.makeBuffer(
            length: MemoryLayout<float2>.stride * numVerticesPerParticle,
            options: staticBufferResourceOption)!
        indexBuffer = device.makeBuffer(
            length: MemoryLayout<UInt16>.stride * numVerticesPerParticle * 3,
            options: staticBufferResourceOption)!

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
        computeHelperFunctions.append(attractToPointFuncString)
        computeHelperFunctions.append(collisionCheckFuncString)
        computeHelperFunctions.append(collisionResolveFuncString)


        setOptions(options, helperFunctions: computeHelperFunctions)

        do {
            let compOp = MTLCompileOptions()
            compOp.fastMathEnabled = true
            compOp.languageVersion = .version2_0
//
//            let vs: [String : NSObject]? = [
//                "HAS_DRAW" : 0 as NSObject,
//                "HAS_LIFETIME" : 0 as NSObject,
//            ]
//
//            for option in options {
//                switch option {
//                case .update:
//                    vs add ["HAS_DRAW" : 0 as NSObject]
//                case .hasLifetime:
//                    rawKernelString += "\n#define HAS_LIFETIME\n"
//                case .interCollision:
//                    rawKernelString += "\n#define HAS_INTERCOLLISION\n"
//                case .attractedToMouse:
//                    rawKernelString += "\n#define HAS_ATTRACTED_TO_MOUSE\n"
//                case .draw:
//                    rawKernelString += "\n#define HAS_DRAW\n"
//                case .borderBound:
//                    rawKernelString += "\n#define HAS_BORDERBOUND\n"
//                case .turbulence:
//                    break
//                case .variableSize:
//                    break
//                case .isHoming:
//                    break
//                }
//            }
//
//            compOp.preprocessorMacros = vs

            print(rawKernelString)
            let libraryC = try device.makeLibrary(source: rawKernelString, options: compOp)
            let computeFunc = libraryC.makeFunction(name: "big_compute")

            try computePipelineState = device.makeComputePipelineState(function: computeFunc!)

        } catch {
            print("Cant compile ParticleSystem options", error.localizedDescription)
            exit(0)
        }
        
        
        buildVertices(numVertices: numVerticesPerParticle)
    }

    public func addEmitter(_ emitter: Emitter) {
        emitters.append(emitter)
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
        
        
        if options.contains(.variableSize) {
            
            renderEncoder.setVertexBytes(&viewportSize,
                                         length: MemoryLayout<float2>.stride,
                                         index: BufferIndex.ViewportSizeIndex.rawValue)
            
            renderEncoder.setVertexBuffer(vertexBuffer,
                                          offset: 0,
                                          index: BufferIndex.VertexIndex.rawValue)
            
            renderEncoder.setVertexBuffer(positionsBuffer,
                                          offset: 0,
                                          index: BufferIndex.PositionIndex.rawValue)
            
            renderEncoder.setVertexBuffer(radiiBuffer,
                                          offset: 0,
                                          index: BufferIndex.RadiusIndex.rawValue)
            
            renderEncoder.setVertexBuffer(colorsBuffer,
                                          offset: 0,
                                          index: BufferIndex.ColorIndex.rawValue)
            
            renderEncoder.setVertexBuffer(lifetimesBuffer,
                                          offset: 0,
                                          index: BufferIndex.lifetimesIndex.rawValue)
            
            renderEncoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: indices.count,
                indexType: .uint16,
                indexBuffer: indexBuffer,
                indexBufferOffset: 0,
                instanceCount: particleCount)
            
        } else {
            quad.draw(renderEncoder: renderEncoder, texture: pTexture)
        }

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
        } else if !options.contains(.variableSize) {
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

        simParam.particleCount = UInt32(particleCount)
        simParam.viewportSize = viewportSize
        simParam.attractPoint = attractPoint
        simParam.mousePos = mousePos
        simParam.currentTime = Float(getTime())
        simParam.gravityForce = enableGravity ? float2(0, gravityForce) : float2(0)
        computeEncoder?.setBytes(&simParam, length: MemoryLayout<SimParam>.stride, index: 9)

        // Reset simParams
        simParam.clearParticles = particleCount > 0 ? false : true
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
        self.simParam.clearParticles = true
    }

    public func addParticleWith(position: float2, color: float4, radius: Float) {

        if self.particleCount == self.maxParticles { return }

        self.particleCount += 1

        self.simParam.shouldAddParticle = true
        self.simParam.newParticlePosition = position
        self.simParam.newParticleVelocity = hasInitialVelocity ? float2(-5,5) : float2(0)
        self.simParam.newParticleRadius = radius
        self.simParam.newParticleMass = Float.pi * radius * radius * radius
        self.simParam.newParticleColor = color
        self.simParam.newParticleLifetime = 1.0
    }
    
    public func setVerticesPerParticle(num: Int) {
        
        numVerticesPerParticle = num
        shouldUpdate = true
    }
    
    private func buildVertices(numVertices: Int) {
        
        precondition(numVertices >= 3, "Can't draw anything with less than 3 vertices")
        
        // Clear previous values
        vertices.removeAll()
        indices.removeAll()
        
        vertices.reserveCapacity(numVertices)
        indices.reserveCapacity(numVertices)
        
        // Add indices
        for num in 0 ..< numVertices - 2 {
            indices.append(UInt16(0))
            indices.append(UInt16(num + 1))
            indices.append(UInt16(num + 2))
        }
        
        // Add vertices
        for num in 0 ..< numVertices {
            let cont = Float(num) * Float.pi * 2 / Float(numVertices)
            vertices.append(float2(cos(cont), sin(cont)))
        }
        
        // Update the GPU buffers
        vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<float2>.stride * vertices.count,
            options: staticBufferResourceOption)!
        
        indexBuffer = device.makeBuffer(
            bytes: indices,
            length: MemoryLayout<UInt16>.stride * indices.count,
            options: staticBufferResourceOption)!
    }
}

