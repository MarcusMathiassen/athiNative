//
//  Quad.swift
//  Athi
//
//  Created by Marcus Mathiassen on 05/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

import MetalKit

final class Quad
{
    var device: MTLDevice
    var pipelineState: MTLRenderPipelineState?
    var gaussianBlurPipelineState: MTLRenderPipelineState?
    
    init(device: MTLDevice)
    {
        self.device = device

        let library = device.makeDefaultLibrary()!
        let vertexFunc = library.makeFunction(name: "quadVert")
        let fragFunc = library.makeFunction(name: "quadFrag")

        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.label = "Quad"
        pipelineDesc.vertexFunction = vertexFunc
        pipelineDesc.fragmentFunction = fragFunc
        pipelineDesc.colorAttachments[0].pixelFormat = Renderer.pixelFormat

        pipelineDesc.colorAttachments[0].isBlendingEnabled = true
        pipelineDesc.colorAttachments[0].rgbBlendOperation = .add
        pipelineDesc.colorAttachments[0].alphaBlendOperation = .add
        pipelineDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDesc.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        pipelineDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            try pipelineState = device.makeRenderPipelineState(descriptor: pipelineDesc)
        } catch {
            print("Pipeline: Creating pipeline state failed")
        }

        let blurfragFunc = library.makeFunction(name: "gaussianBlurFrag")

        let blurPipelineDesc = MTLRenderPipelineDescriptor()
        blurPipelineDesc.label = "GaussianBlur"
        blurPipelineDesc.vertexFunction = vertexFunc
        blurPipelineDesc.fragmentFunction = blurfragFunc
        blurPipelineDesc.colorAttachments[0].pixelFormat = Renderer.pixelFormat

        do {
            try gaussianBlurPipelineState = device.makeRenderPipelineState(descriptor: blurPipelineDesc)
        } catch {
            print("Pipeline: Creating pipeline state failed")
        }
    }
    
    func gaussianBlur(
        renderEncoder: MTLRenderCommandEncoder,
        texture: MTLTexture,
        sigma: Float,
        samples: Int)
    {
        
        var dir: float2
        renderEncoder.pushDebugGroup("Gauassian Blur")
        renderEncoder.setTriangleFillMode(.fill)
        renderEncoder.setRenderPipelineState(gaussianBlurPipelineState!)
        
        renderEncoder.setFragmentBytes(&viewportSize, length: MemoryLayout<float2>.stride, index: 0)
        renderEncoder.setFragmentTexture(texture, index: 0)

        
        for iter in 0 ..< samples {
            
            renderEncoder.pushDebugGroup("Sample: " + String(iter))
            
            dir = float2(sigma, 0)
            renderEncoder.pushDebugGroup("Horizontal")
            renderEncoder.setFragmentBytes(&dir, length: MemoryLayout<float2>.stride, index: 1)
            renderEncoder.drawPrimitives(
                type: .triangle,
                vertexStart: 0,
                vertexCount: 6
            )
            renderEncoder.popDebugGroup()

            renderEncoder.pushDebugGroup("Vertical")

            dir = float2(0, sigma)
            renderEncoder.setFragmentBytes(&dir, length: MemoryLayout<float2>.stride, index: 1)
            renderEncoder.drawPrimitives(
                type: .triangle,
                vertexStart: 0,
                vertexCount: 6
            )
            renderEncoder.popDebugGroup()
        
            renderEncoder.popDebugGroup()
        }

        renderEncoder.popDebugGroup()
    }

    func draw(renderEncoder: MTLRenderCommandEncoder, texture: MTLTexture)
    {
        renderEncoder.pushDebugGroup("Draw Fullscreen Quad")
        renderEncoder.setRenderPipelineState(pipelineState!)
        renderEncoder.setTriangleFillMode(.fill)

        renderEncoder.setFragmentTexture(texture, index: 0)

        renderEncoder.drawPrimitives(
            type: .triangle,
            vertexStart: 0,
            vertexCount: 6
        )
        renderEncoder.popDebugGroup()
    }
}
