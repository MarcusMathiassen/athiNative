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
    var pixelFormat: MTLPixelFormat = .bgra8Unorm

    var deltaTime: Float = 0.0
}

final class Renderer: NSObject, MTKViewDelegate
{
    var wireframeMode: Bool = false
    var fillMode: MTLTriangleFillMode = .fill

    static var clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    static var pixelFormat = MTLPixelFormat.bgra8Unorm

    var framerate: Int = 0
    var frametime: Float = 0
    var deltaTime: Float = 0

    var particleSystem: ParticleSystem

    // Tripple buffering
    var maxNumInFlightBuffers = 3
    var currentQueue = 0
    var inFlightSemaphore = DispatchSemaphore(value: 0)
    //

    var device: MTLDevice
    let commandQueues: [MTLCommandQueue?]

    init?(view: MTKView) {
        device = view.device!
        particleSystem = ParticleSystem(device: device)
        commandQueues = [device.makeCommandQueue()!, device.makeCommandQueue()!, device.makeCommandQueue()!]

        inFlightSemaphore = DispatchSemaphore(value: maxNumInFlightBuffers)

        super.init()

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


        view.autoResizeDrawable = true // auto updates the views resolution on resizing
        view.preferredFramesPerSecond = 60
        view.sampleCount = 1
        view.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0)
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.framebufferOnly = false


        print("Argument buffer support:", device.argumentBuffersSupport.rawValue)
        print("ReadWrite texture support:", device.readWriteTextureSupport.rawValue)
        print("maxThreadsPerThreadgroup:", device.maxThreadsPerThreadgroup)
    }

    func draw(in view: MTKView) {

        inFlightSemaphore.wait()

        currentQueue = (currentQueue + 1) % maxNumInFlightBuffers

        /// Per frame updates hare

        let commandBuffer = (commandQueues[currentQueue]?.makeCommandBuffer())!

        commandBuffer.label = "MyCommandBuffer"

        commandBuffer.addCompletedHandler { (commandBuffer) in
            self.inFlightSemaphore.signal()
        }

        var frameDescriptor = FrameDescriptor()
        frameDescriptor.fillMode = fillMode
        frameDescriptor.framebufferSize = float2(framebufferWidth, framebufferHeight)
        frameDescriptor.viewportSize = frameDescriptor.framebufferSize
        frameDescriptor.deltaTime = deltaTime
        frameDescriptor.pixelFormat = .bgra8Unorm

        #if os(macOS)
        let bck = backgroundColor.cgColor
        frameDescriptor.clearColor = MTLClearColor(red: Double(bck.components![0]), green: Double(bck.components![1]), blue: Double(bck.components![2]), alpha: Double(bck.components![3]))
        #else
        frameDescriptor.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        #endif

        if particleColorCycle {
            particleSystem.particleColor = colorOverTime(getTime())
        }

        let startTime = getTime()

        updateInput()

        updateVariables()

        particleSystem.update(commandBuffer: commandBuffer)
        particleSystem.draw(
            view: view,
            frameDescriptor: frameDescriptor,
            commandBuffer: commandBuffer
        )

        commandBuffer.present(view.currentDrawable!)
        commandBuffer.commit()
        frametime = Float((getTime() - startTime) * 1000.0)
        framerate = Int(1000 / frametime)
    }

    func updateVariables() {
    }

    func updateInput() {
        if !isMouseDown {
//            particleSystem.shouldRepel = false
            gmouseAttachedToIDs.removeAll()
            return
        }

        switch gMouseOption {
        case MouseOption.Spawn:
            particleSystem.addParticleWith(position: mousePos, color: particleSystem.particleColor, radius: particleSize)
            particleSystem.addParticleWith(position: mousePos, color: particleSystem.particleColor, radius: particleSize)
            particleSystem.addParticleWith(position: mousePos, color: particleSystem.particleColor, radius: particleSize)
            particleSystem.addParticleWith(position: mousePos, color: particleSystem.particleColor, radius: particleSize)
            particleSystem.addParticleWith(position: mousePos, color: particleSystem.particleColor, radius: particleSize)
            particleSystem.addParticleWith(position: mousePos, color: particleSystem.particleColor, radius: particleSize)
            particleSystem.addParticleWith(position: mousePos, color: particleSystem.particleColor, radius: particleSize)
            particleSystem.addParticleWith(position: mousePos, color: particleSystem.particleColor, radius: particleSize)
            particleSystem.addParticleWith(position: mousePos, color: particleSystem.particleColor, radius: particleSize)
            particleSystem.addParticleWith(position: mousePos, color: particleSystem.particleColor, radius: particleSize)

        case MouseOption.Drag:
             break
//            particleSystem.shouldRepel = false
//            let particleIDsToDrag = particleSystem.getParticlesInCircle(position: mousePos, radius: mouseSize)
//            if gmouseAttachedToIDs.isEmpty {
//                for id in particleIDsToDrag {
//                    gmouseAttachedToIDs.append(id)
//                }
//            }
//
//            particleSystem.goTowardsPoint(mousePos, particleIDs: gmouseAttachedToIDs)

        case MouseOption.Color:
             break
//            let particleIDsToDrag = particleSystem.getParticlesInCircle(position: mousePos, radius: mouseSize)
//            particleSystem.colorParticles(IDs: particleIDsToDrag, color: particleSystem.particleColor)

        case MouseOption.Repel:
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

        let mainTextureDesc = MTLTextureDescriptor()
        mainTextureDesc.height = Int(framebufferHeight)
        mainTextureDesc.width = Int(framebufferWidth)
        mainTextureDesc.sampleCount = 1
        mainTextureDesc.textureType = .type2D
        mainTextureDesc.pixelFormat = Renderer.pixelFormat
        mainTextureDesc.resourceOptions = .storageModePrivate
        mainTextureDesc.usage = .shaderRead
        particleSystem.inTexture = device.makeTexture(descriptor: mainTextureDesc)!
        mainTextureDesc.usage = .shaderWrite
        particleSystem.outTexture = device.makeTexture(descriptor: mainTextureDesc)!
        particleSystem.finalTexture = device.makeTexture(descriptor: mainTextureDesc)!


        #if os(macOS)
            let area = NSTrackingArea(rect: view.bounds, options: [.activeAlways, .mouseMoved, .enabledDuringMouseDrag], owner: view, userInfo: nil)
            view.addTrackingArea(area)
        #endif
    }
}
