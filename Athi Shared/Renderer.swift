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
import MetalPerformanceShaders // gaussian blur


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
    
    var enablePostProcessing: Bool = false
    
    var particleSystem: ParticleSystem
    
    var device: MTLDevice?
    let commandQueue: MTLCommandQueue?

    var scene: Scene
    var quad: Quad?
    
    var texture: MTLTexture?
    var textureResolve: MTLTexture?
    
    init?(view: MTKView) {
    
        view.autoResizeDrawable = true // auto updates the views resolution on resizing
        view.preferredFramesPerSecond = 60
        view.sampleCount = 4
        view.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0)
        view.colorPixelFormat = MTLPixelFormat.bgra8Unorm_srgb
        view.framebufferOnly = false
    
        device = view.device!
        
        let textureDesc = MTLTextureDescriptor()
        textureDesc.height = Int(framebufferHeight)
        textureDesc.width = Int(framebufferWidth)
        textureDesc.depth = 1
        textureDesc.sampleCount = 4
        textureDesc.textureType = .type2DMultisample
        textureDesc.pixelFormat = view.colorPixelFormat
        textureDesc.resourceOptions = .storageModePrivate
        textureDesc.usage = .renderTarget
        texture = device?.makeTexture(descriptor: textureDesc)

        
        let textureResolveDesc = MTLTextureDescriptor()
        textureResolveDesc.height = Int(framebufferHeight)
        textureResolveDesc.width = Int(framebufferWidth)
        textureResolveDesc.depth = 1
        textureResolveDesc.textureType = .type2D
        textureResolveDesc.pixelFormat = view.colorPixelFormat
        textureResolveDesc.resourceOptions = .storageModePrivate
        textureResolveDesc.usage = .shaderRead
        textureResolve = device?.makeTexture(descriptor: textureResolveDesc)
        
        quad = Quad(device: device)

        guard let queue = self.device?.makeCommandQueue() else { return nil }
        commandQueue = queue
        
        particleSystem = ParticleSystem(device: device)
        
        scene = Scene(device: device!)

        super.init()
    }

    func draw(in view: MTKView) {
        
        updateInput()
        
        updateVariables()
        
        /// Per frame updates hare
        
        let commandBuffer = commandQueue?.makeCommandBuffer()
        commandBuffer?.label = "MyCommandBuffer"
        
        let blackClearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        
        let renderPassDesc = view.currentRenderPassDescriptor
    
        if renderPassDesc != nil {

            if (!enablePostProcessing) {
                
                let renderEncoder = commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDesc!)
                
                renderEncoder?.label = "Main pass"
                renderEncoder?.setTriangleFillMode(fillMode)
                
                let vp = makeOrtho(left: 0, right: screenWidth, bottom: 0, top: screenHeight, near: -1, far: 1)
                
                // Go through all scenes and render
                particleSystem.update()
                particleSystem.draw(renderEncoder: renderEncoder, vp: vp)
                
                renderEncoder?.endEncoding()
                commandBuffer?.present(view.currentDrawable!)
                commandBuffer?.commit()
                return
            }
            
            renderPassDesc?.colorAttachments[0].clearColor = blackClearColor
            renderPassDesc?.colorAttachments[0].loadAction = .clear
            renderPassDesc?.colorAttachments[0].texture = texture
            renderPassDesc?.colorAttachments[0].resolveTexture = textureResolve
            renderPassDesc?.colorAttachments[0].storeAction = .storeAndMultisampleResolve

            
            var renderEncoder = commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDesc!)
            
            renderEncoder?.label = "Main pass"
            renderEncoder?.setTriangleFillMode(fillMode)
            
            let vp = makeOrtho(left: 0, right: screenWidth, bottom: 0, top: screenHeight, near: -1, far: 1)
            
            // Go through all scenes and render
            particleSystem.update()
            particleSystem.draw(renderEncoder: renderEncoder, vp: vp)
            renderEncoder?.endEncoding()
            
            
            // Second pass
            
            renderPassDesc?.colorAttachments[0].clearColor = blackClearColor
            renderPassDesc?.colorAttachments[0].loadAction = .clear
            renderPassDesc?.colorAttachments[0].texture = texture
            renderPassDesc?.colorAttachments[0].resolveTexture = view.currentDrawable?.texture
            renderPassDesc?.colorAttachments[0].storeAction = .storeAndMultisampleResolve
            
            renderEncoder = commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDesc!)
            
            renderEncoder?.label = "Main pass 2"
            renderEncoder?.setTriangleFillMode(fillMode)
            
            // Go through all scenes and render
            particleSystem.update()
            particleSystem.draw(renderEncoder: renderEncoder, vp: vp)
            
            quad?.draw(renderEncoder: renderEncoder, texture: textureResolve, direction: float2(0,5))
            quad?.draw(renderEncoder: renderEncoder, texture: textureResolve, direction: float2(5,0))
            
            renderEncoder?.endEncoding()
            commandBuffer?.present(view.currentDrawable!)
        }

        commandBuffer?.commit()
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
        textureDesc.depth = 1
        textureDesc.sampleCount = 4
        textureDesc.textureType = .type2DMultisample
        textureDesc.pixelFormat = view.colorPixelFormat
        textureDesc.resourceOptions = .storageModePrivate
        textureDesc.usage = .renderTarget
        texture = device?.makeTexture(descriptor: textureDesc)
        
        
        let textureResolveDesc = MTLTextureDescriptor()
        textureResolveDesc.height = Int(framebufferHeight)
        textureResolveDesc.width = Int(framebufferWidth)
        textureResolveDesc.depth = 1
        textureResolveDesc.textureType = .type2D
        textureResolveDesc.pixelFormat = view.colorPixelFormat
        textureResolveDesc.resourceOptions = .storageModePrivate
        textureResolveDesc.usage = .shaderRead
        textureResolve = device?.makeTexture(descriptor: textureResolveDesc)
        
        let area = NSTrackingArea(rect: view.bounds, options: [.activeAlways, .mouseMoved, .enabledDuringMouseDrag], owner: view, userInfo: nil)
        view.addTrackingArea(area)
        #endif
        
    }
}
