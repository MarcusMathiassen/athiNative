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

class Renderer: NSObject, MTKViewDelegate {
    var wireframeMode: Bool = false
    var fillMode: MTLTriangleFillMode = .fill

    var primitiveRenderer: PrimitiveRenderer

    var framerate: Int = 0
    var frametime: Float = 0
    var deltaTime: Float = 0

    var enableMPSPostProcessing: Bool = true
    var enablePostProcessing: Bool = true
    var postProcessingSamples: Int = 2
    var blurStrength: Float = 4

    var particleSystem: ParticleSystem

    var device: MTLDevice
    let commandQueue: MTLCommandQueue?

    var scene: Scene
    var quad: Quad
    
    var emitter: Emitter

    var texture: MTLTexture

    init?(view: MTKView)
    {
        view.autoResizeDrawable = true // auto updates the views resolution on resizing
        view.preferredFramesPerSecond = 60
        view.sampleCount = 1
        view.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0)
        view.colorPixelFormat = MTLPixelFormat.bgr10a2Unorm
        view.framebufferOnly = false

        device = view.device!
        primitiveRenderer = PrimitiveRenderer(device: device)

        let textureDesc = MTLTextureDescriptor()
        textureDesc.height = Int(framebufferHeight)
        textureDesc.width = Int(framebufferWidth)
        textureDesc.sampleCount = 1
        textureDesc.textureType = .type2D
        textureDesc.pixelFormat = view.colorPixelFormat
        textureDesc.resourceOptions = .storageModePrivate
        textureDesc.usage = [.shaderRead, .shaderWrite]
        texture = device.makeTexture(descriptor: textureDesc)!

        quad = Quad(device: device)

        guard let queue = self.device.makeCommandQueue() else
        {
             return nil 
        }
        
        commandQueue = queue

        particleSystem = ParticleSystem(device: device)
        emitter = Emitter(device: device)
        scene = Scene(device: device)

        super.init()
    }

    func draw(in view: MTKView) {
        if particleColorCycle {
            particleSystem.particleColor = colorOverTime(getTime() * 0.5)
        }

        let startTime = getTime()

        updateInput()

        updateVariables()

        /// Per frame updates hare

        guard let commandBuffer = commandQueue?.makeCommandBuffer() else {
            return
        }
        commandBuffer.label = "MyCommandBuffer"

        #if os(macOS)
            let bck = backgroundColor.cgColor
            let clearColor = MTLClearColor(red: Double(bck.components![0]), green: Double(bck.components![1]), blue: Double(bck.components![2]), alpha: Double(bck.components![3]))
        #else
            let clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        #endif

        let renderPassDesc = view.currentRenderPassDescriptor!
        renderPassDesc.colorAttachments[0].clearColor = clearColor
        renderPassDesc.colorAttachments[0].texture = texture
        renderPassDesc.colorAttachments[0].loadAction = .clear
        renderPassDesc.colorAttachments[0].storeAction = .store

        var renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc)!

        renderEncoder.label = "Draw to texture"
        renderEncoder.setTriangleFillMode(fillMode)

        let vp = makeOrtho(left: 0, right: screenWidth, bottom: 0, top: screenHeight, near: -1, far: 1)

        particleSystem.update()
        
        
//        emitter.update()
//        emitter.draw(renderEncoder: renderEncoder, vp: vp)
        
        // Draw particles
        particleSystem.draw(renderEncoder: renderEncoder, vp: vp)

        if enablePostProcessing {
            // Blur
            for _ in 0 ..< postProcessingSamples {
                quad.gaussianBlur(renderEncoder: renderEncoder, texture: texture, sigma: blurStrength)
            }
            
//            emitter.draw(renderEncoder: renderEncoder, vp: vp)

            // Draw particles
            particleSystem.draw(renderEncoder: renderEncoder, vp: vp)
        }
        
        // Draw to view
        renderEncoder.endEncoding()
//
//         let kernel = MPSImageGaussianBlur(device: device, sigma: blurStrength)
//         kernel.encode(commandBuffer: commandBuffer, inPlaceTexture: &texture, fallbackCopyAllocator: nil)
//
//        
        renderPassDesc.colorAttachments[0].clearColor = clearColor
        renderPassDesc.colorAttachments[0].texture = view.currentDrawable?.texture
        renderPassDesc.colorAttachments[0].loadAction = .clear
        renderPassDesc.colorAttachments[0].storeAction = .store

        renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc)!
        renderEncoder.label = "Draw texture to view"
        quad.draw(renderEncoder: renderEncoder, texture: texture)
        
        renderEncoder.endEncoding()
        commandBuffer.present(view.currentDrawable!)
        commandBuffer.commit()
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
        case MouseOption.Spawn:
            particleSystem.addParticle(position: mousePos, color: particleSystem.particleColor, radius: particleSize)
            particleSystem.addParticle(position: mousePos, color: particleSystem.particleColor, radius: particleSize)
            particleSystem.addParticle(position: mousePos, color: particleSystem.particleColor, radius: particleSize)
            particleSystem.addParticle(position: mousePos, color: particleSystem.particleColor, radius: particleSize)
            particleSystem.addParticle(position: mousePos, color: particleSystem.particleColor, radius: particleSize)
            particleSystem.addParticle(position: mousePos, color: particleSystem.particleColor, radius: particleSize)
            particleSystem.addParticle(position: mousePos, color: particleSystem.particleColor, radius: particleSize)
            particleSystem.addParticle(position: mousePos, color: particleSystem.particleColor, radius: particleSize)
            particleSystem.addParticle(position: mousePos, color: particleSystem.particleColor, radius: particleSize)
            particleSystem.addParticle(position: mousePos, color: particleSystem.particleColor, radius: particleSize)

        case MouseOption.Drag:
            let particleIDsToDrag = particleSystem.getParticlesInCircle(position: mousePos, radius: mouseSize)
            if gmouseAttachedToIDs.isEmpty {
                for id in particleIDsToDrag {
                    gmouseAttachedToIDs.append(id)
                }
            }
            for id in gmouseAttachedToIDs {
                particleSystem.attractionForce(p: &particleSystem.particles[id], point: mousePos)
            }

        case MouseOption.Color:
            let particleIDsToDrag = particleSystem.getParticlesInCircle(position: mousePos, radius: mouseSize)
            particleSystem.colorParticles(IDs: particleIDsToDrag, color: particleSystem.particleColor)
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

        #if os(macOS)

            let textureDesc = MTLTextureDescriptor()
            textureDesc.height = Int(framebufferHeight)
            textureDesc.width = Int(framebufferWidth)
            textureDesc.sampleCount = 1
            textureDesc.textureType = .type2D
            textureDesc.pixelFormat = view.colorPixelFormat
            textureDesc.resourceOptions = .storageModePrivate
            textureDesc.usage = [.shaderRead, .shaderWrite]
            texture = device.makeTexture(descriptor: textureDesc)!

            let area = NSTrackingArea(rect: view.bounds, options: [.activeAlways, .mouseMoved, .enabledDuringMouseDrag], owner: view, userInfo: nil)
            view.addTrackingArea(area)
        #endif
    }
}
