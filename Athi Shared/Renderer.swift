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
import simd

var mousePos = float2(0,0)
var screenWidth = Float()
var screenHeight = Float()

var framebufferHeight: Float = 0
var framebufferWidth: Float = 0

var viewport = float2(512,512)

var wireframeMode: Bool = false
var fillMode: MTLTriangleFillMode = .fill

struct Vertex {
    var position: float2
    var color: float4
    var uv: float2
}

struct Uniform {
    var modelMatrix: float4x4
}

/**
 Stores all vertices sent to the GPU. Cleared each frame.
 */
var gVertices: [Vertex] = []

/**
 Stores all uniforms sent to the GPU. Cleared each frame.
 */
var gUniforms: [Uniform] = []

func addTransform(_ transform: Transform) {
    let ortho = makeOrtho(left: 0, right: screenWidth, bottom: 0, top: screenHeight, near: -1, far: 1)

    let model = ortho * transform.getModel()
    gUniforms.append(Uniform(modelMatrix: model))
}

class Renderer: NSObject, MTKViewDelegate {
    
    
    var framerate: Int = 0
    var frametime: Float = 0
    var deltaTime: Float = 0
    
    var particleSystem: ParticleSystem
    
    var device: MTLDevice?
    let commandQueue: MTLCommandQueue?

    var scene: Scene
    
    init?(view: MTKView) {
                
        #if os(macOS)
            pixelScale = Float(NSScreen.screens[0].backingScaleFactor)
            let maxRefreshRate = 144
        
        print("pixelScale:", pixelScale)

        #else
            let maxRefreshRate =  UIScreen.screens[0].maximumFramesPerSecond
        #endif
        
        print("maxRefreshRate:", maxRefreshRate)
        
        view.autoResizeDrawable = true // auto updates the views resolution on resizing
        view.preferredFramesPerSecond = maxRefreshRate
        view.sampleCount = 2
        view.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0)
        view.colorPixelFormat = MTLPixelFormat.bgra8Unorm_srgb
        
        device = view.device!

        guard let queue = self.device?.makeCommandQueue() else { return nil }
        commandQueue = queue
        
        particleSystem = ParticleSystem(device: device)
        
        scene = Scene(device: device!)

        super.init()
    }
    
    func updateVariables() {
        
        if !wireframeMode {
            fillMode = .lines
        } else  {
            fillMode = .fill
        }
        
    }
    
    func updateInput() {
        
        if(isKeyPressed(key: KEY_CODES.Key_W)) {
            
//            particleSystem.addParticle(position: mousePos, color: float4(1), radius: 10)
            
//            scene.addTriangle(mousePos, 10)
        }
        
        if (isMouseDown) {
            particleSystem.addParticle(position: mousePos, color: colorOverTime(getTime()), radius: particleSize)
            particleSystem.addParticle(position: mousePos, color: colorOverTime(getTime()), radius: particleSize)
            particleSystem.addParticle(position: mousePos, color: colorOverTime(getTime()), radius: particleSize)
            particleSystem.addParticle(position: mousePos, color: colorOverTime(getTime()), radius: particleSize)
            particleSystem.addParticle(position: mousePos, color: colorOverTime(getTime()), radius: particleSize)
            particleSystem.addParticle(position: mousePos, color: colorOverTime(getTime()), radius: particleSize)
            particleSystem.addParticle(position: mousePos, color: colorOverTime(getTime()), radius: particleSize)

//            scene.addTriangle(mousePos, 10)
        }
        
    }

    func draw(in view: MTKView) {
        
        updateInput()
        
        updateVariables()
        
        /// Per frame updates hare
        
        let commandBuffer = commandQueue?.makeCommandBuffer()
        commandBuffer?.label = "MyCommandBuffer"
        
        let renderPassDescriptor = view.currentRenderPassDescriptor
        if renderPassDescriptor != nil {
            
            let renderEncoder = commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDescriptor!)
            
            renderEncoder?.setTriangleFillMode(fillMode)
            
            let vp = makeOrtho(left: 0, right: screenWidth, bottom: 0, top: screenHeight, near: -1, far: 1)
            
            // Go through all scenes and render
            scene.update()
            scene.render(renderEncoder: renderEncoder, vp: vp)

            particleSystem.update()
            particleSystem.draw(renderEncoder: renderEncoder, vp: vp)
            
            renderEncoder?.endEncoding()
            commandBuffer?.present(view.currentDrawable!)
        }

        commandBuffer?.commit()
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        /// Respond to drawable size or orientation changes here

        
        screenWidth = Float(size.width)
        screenHeight = Float(size.height)
        
        framebufferWidth = screenWidth
        framebufferHeight = screenHeight
        
        viewport.x = Float(view.drawableSize.width) / 2
        viewport.y = Float(view.drawableSize.height) / 2

        #if os(macOS)
        let area = NSTrackingArea(rect: view.bounds, options: [.activeAlways, .mouseMoved, .enabledDuringMouseDrag], owner: view, userInfo: nil)
        view.addTrackingArea(area)
        #endif
        
    }
}
