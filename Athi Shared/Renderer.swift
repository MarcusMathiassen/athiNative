//
//  Renderer.swift
//  Athi Shared
//
//  Created by Marcus Mathiassen on 02/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

// Our platform independent renderer class

import Metal
import MetalKit
import MetalPerformanceShaders // gaussian blur
import simd.vector_types

var mousePos = float2(0, 0)
var screenWidth = Float()
var screenHeight = Float()

var framebufferHeight: Float = 0
var framebufferWidth: Float = 0

var viewport = float2(512, 512)

struct FrameDescriptor {

    var fillMode: MTLTriangleFillMode = .fill

    var framebufferSize: float2 = float2(0)
    var viewportSize: float2 = float2(0)

    var clearColor: MTLClearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    var pixelFormat: MTLPixelFormat = Renderer.pixelFormat
    var deltaTime: Float = 0.0
}

final class Renderer: NSObject, MTKViewDelegate {

    var wireframeMode: Bool = false
    var fillMode: MTLTriangleFillMode = .fill

    static var clearColor = MTLClearColor(red: 9/255, green: 9/255, blue: 9/255, alpha: 1)
    static var pixelFormat = MTLPixelFormat.bgra8Unorm

    var framerate: Int = 0
    var frametime: Float = 0
    var deltaTime: Float = 0

    var particleSystem: ParticleSystem

    // Tripple buffering
    var maxNumInFlightBuffers = 3
    var currentQueue = 0
    var inFlightSemaphore: DispatchSemaphore

    var device: MTLDevice

    let commandQueue: MTLCommandQueue

    public func printDeviceInfo(_ device: MTLDevice) {
        #if os(macOS)
        let devices = MTLCopyAllDevices()
        print("Available devices:")
        for device in devices {
            print((device.name == self.device.name) ? "*" : " ", device.name)
        }

        print("isHeadless:", device.isHeadless)
        print("isLowPower:", device.isLowPower)
        print("isRemovable:", device.isRemovable)
        #endif

        print("argumentBuffersSupport:", device.argumentBuffersSupport.rawValue)
        print("Argument buffer support:", device.argumentBuffersSupport.rawValue)
        print("ReadWrite texture support:", device.readWriteTextureSupport.rawValue)
        print("maxThreadsPerThreadgroup:", device.maxThreadsPerThreadgroup)

        // CrossPlatform stuff
        #if os(macOS)
        print("macOS_GPUFamily1_v1: ", device.supportsFeatureSet(.macOS_GPUFamily1_v1))
        print("macOS_GPUFamily1_v2: ", device.supportsFeatureSet(.macOS_GPUFamily1_v2))
        print("macOS_GPUFamily1_v3: ", device.supportsFeatureSet(.macOS_GPUFamily1_v3))
        print("macOS_ReadWriteTextureTier2: ", device.supportsFeatureSet(.macOS_ReadWriteTextureTier2))
        print("osx_GPUFamily1_v1: ", device.supportsFeatureSet(.osx_GPUFamily1_v1))
        print("osx_GPUFamily1_v2: ", device.supportsFeatureSet(.osx_GPUFamily1_v2))
        print("osx_ReadWriteTextureTier2: ", device.supportsFeatureSet(.osx_ReadWriteTextureTier2))
        #else
        print("iOS_GPUFamily1_v1: ", device.supportsFeatureSet(.iOS_GPUFamily1_v1))
        print("iOS_GPUFamily1_v2: ", device.supportsFeatureSet(.iOS_GPUFamily1_v2))
        print("iOS_GPUFamily1_v3: ", device.supportsFeatureSet(.iOS_GPUFamily1_v3))
        print("iOS_GPUFamily1_v4: ", device.supportsFeatureSet(.iOS_GPUFamily1_v4))
        print("iOS_GPUFamily2_v1: ", device.supportsFeatureSet(.iOS_GPUFamily2_v1))
        print("iOS_GPUFamily2_v2: ", device.supportsFeatureSet(.iOS_GPUFamily2_v2))
        print("iOS_GPUFamily2_v3: ", device.supportsFeatureSet(.iOS_GPUFamily2_v3))
        print("iOS_GPUFamily2_v4: ", device.supportsFeatureSet(.iOS_GPUFamily2_v4))
        print("iOS_GPUFamily3_v1: ", device.supportsFeatureSet(.iOS_GPUFamily3_v1))
        print("iOS_GPUFamily3_v2: ", device.supportsFeatureSet(.iOS_GPUFamily3_v2))
        print("iOS_GPUFamily3_v3: ", device.supportsFeatureSet(.iOS_GPUFamily3_v3))
        print("iOS_GPUFamily4_v1: ", device.supportsFeatureSet(.iOS_GPUFamily4_v1))
        #endif
    }

    init?(view: MTKView) {

        device = view.device!

        inFlightSemaphore = DispatchSemaphore(value: maxNumInFlightBuffers)

        commandQueue = device.makeCommandQueue()!

        view.autoResizeDrawable = true // auto updates the views resolution on resizing
        view.preferredFramesPerSecond = 60
        view.sampleCount = 1
        view.clearColor = Renderer.clearColor
        view.colorPixelFormat = Renderer.pixelFormat
        view.framebufferOnly = false
        view.enableSetNeedsDisplay = false

        let myParticleOptions: [ParticleOption] = [
                        .lifetime,
//                        .homing,
                        .respawns,
            //            .turbulence,
            //            .attractedToMouse,
//                        .intercollision,
                        .borderBound,
//                        .drawToTexture,
//                        .canAddParticles
        ]
        particleSystem = ParticleSystem(
            device: device,
            options: myParticleOptions,
            maxParticles: 10_000
        )

            var emitterDesc = PSEmitterDescriptor()
            emitterDesc.isActive = true
            emitterDesc.mozzleSpread = 2
            emitterDesc.spawnPoint = float2(framebufferWidth/2, 0)
            emitterDesc.spawnDirection = float2(0, 1)
            emitterDesc.spawnRate = 1000
            emitterDesc.particleLifetime = 5.0
            emitterDesc.particleSize = 5
            emitterDesc.particleColor = float4(1, 0.47, 0.47, 1)
            emitterDesc.options = [.lifetime, .respawns]
            var redEmitter = particleSystem.makeEmitter(descriptor: emitterDesc)
            _ = particleSystem.addEmitter(&redEmitter)

        super.init()

        printDeviceInfo(device)
    }

    func draw(in view: MTKView) {

//        _ = self.inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)

        let startTime = getTime()

//        currentQueue = (currentQueue + 1) % maxNumInFlightBuffers

        let commandBuffer = commandQueue.makeCommandBuffer()!

        commandBuffer.label = "CommandBuffer: " + String(currentQueue)

//        let blocker = inFlightSemaphore
//        commandBuffer.addCompletedHandler { (_) in
//            blocker.signal()
//        }

        var frameDescriptor = FrameDescriptor()
        frameDescriptor.fillMode = fillMode
        frameDescriptor.framebufferSize = float2(framebufferWidth, framebufferHeight)
        frameDescriptor.viewportSize = frameDescriptor.framebufferSize
        frameDescriptor.deltaTime = deltaTime
        frameDescriptor.pixelFormat = Renderer.pixelFormat

        #if os(macOS)
        let bck = backgroundColor.cgColor
        frameDescriptor.clearColor = MTLClearColor(
            red: Double(bck.components![0]),
            green: Double(bck.components![1]),
            blue: Double(bck.components![2]),
            alpha: Double(bck.components![3]))
        #else
        frameDescriptor.clearColor = Renderer.clearColor
        #endif

        if gParticleColorCycle {
            particleSystem.particleColor = colorOverTime(getTime())
        }

        updateInput()

        updateVariables()

        particleSystem.update(commandBuffer: commandBuffer, computeDevice: gComputeDeviceOption)
        particleSystem.draw(view: view, frameDescriptor: frameDescriptor, commandBuffer: commandBuffer)

        if particleSystem.particleCount == 0 {
            // Clear the screen
            let renderPassDesc = view.currentRenderPassDescriptor!
            let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc)
            renderEncoder?.endEncoding()
        }

        commandBuffer.present(view.currentDrawable!)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        frametime = Float((getTime() - startTime) * 1000.0)
        framerate = Int(1000 / frametime)

    }

    func updateVariables() {
    }

    func updateInput() {
        if !isMouseDown {
            gmouseAttachedToIDs.removeAll()
            return
        }

        switch gMouseOption {
        case MouseOption.spawn:

            var emitterDesc = PSEmitterDescriptor()
            emitterDesc.isActive = true
            emitterDesc.mozzleSpread = 2
            emitterDesc.spawnPoint = mousePos
            emitterDesc.spawnDirection = float2(0, 0)
            emitterDesc.spawnRate = 100
            emitterDesc.particleLifetime = 3
            emitterDesc.particleSize = gParticleSize
            emitterDesc.particleColor = particleSystem.particleColor
            emitterDesc.options = [.lifetime, .respawns]
            var redEmitter = particleSystem.makeEmitter(descriptor: emitterDesc)
            _ = particleSystem.addEmitter(&redEmitter)

        case MouseOption.drag:
             break

        case MouseOption.color:
             break

        case MouseOption.repel:
            particleSystem.shouldRepel = true
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {

        /// Respond to drawable size or orientation changes here

        screenWidth = Float(size.width)
        screenHeight = Float(size.height)

        framebufferWidth = screenWidth
        framebufferHeight = screenHeight

        viewportSize.x = framebufferWidth
        viewportSize.y = framebufferHeight

        let textureDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Renderer.pixelFormat,
            width: Int(framebufferWidth),
            height: Int(framebufferHeight),
            mipmapped: false)

        textureDesc.resourceOptions = .storageModePrivate

        textureDesc.usage = [.shaderRead, .renderTarget]
        particleSystem.inTexture = device.makeTexture(descriptor: textureDesc)!

        textureDesc.usage = [.shaderRead, .shaderWrite, .renderTarget]
        particleSystem.outTexture = device.makeTexture(descriptor: textureDesc)!
        particleSystem.finalTexture = device.makeTexture(descriptor: textureDesc)!
        particleSystem.pTexture = device.makeTexture(descriptor: textureDesc)!

        #if os(macOS)
            let area = NSTrackingArea(
                rect: view.bounds,
                options: [.activeAlways, .mouseMoved, .enabledDuringMouseDrag],
                owner: view,
                userInfo: nil)
            view.addTrackingArea(area)
        #endif
    }
}
