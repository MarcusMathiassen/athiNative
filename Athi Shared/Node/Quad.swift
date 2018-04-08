//
//  Quad.swift
//  Athi
//
//  Created by Marcus Mathiassen on 05/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

import MetalKit


class Quad {
    
    struct Vertex {
        var position: float2
        var uv: float2
    }
    
    var vertexBuffer: MTLBuffer?
    
    weak var device: MTLDevice?
    var pipelineState: MTLRenderPipelineState?
    var gaussianBlurPipelineState: MTLRenderPipelineState?
    
    init(device: MTLDevice?) {
        self.device = device
        
        let vertices: [Vertex] = [
           Vertex(position: float2(-1, 1),  uv: float2(0, 1)),
           Vertex(position: float2( 1, 1),  uv: float2(1, 1)),
           Vertex(position: float2( 1,-1),  uv: float2(1, 0)),
           
           Vertex(position: float2(-1, 1),  uv: float2(0, 1)),
           Vertex(position: float2( 1,-1),  uv: float2(1, 0)),
           Vertex(position: float2(-1,-1),  uv: float2(0, 0)),
        ]
        
        vertexBuffer = device?.makeBuffer(bytes: vertices, length: MemoryLayout<Vertex>.stride * vertices.count, options: .cpuCacheModeWriteCombined)
        
        let library = device?.makeDefaultLibrary()!
        let vertexFunc = library?.makeFunction(name: "quadVert")
        let fragFunc = library?.makeFunction(name: "quadFrag")
        
        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.label = "Quad"
        pipelineDesc.vertexFunction = vertexFunc
        pipelineDesc.fragmentFunction = fragFunc
        pipelineDesc.colorAttachments[0].pixelFormat = MTLPixelFormat.bgra8Unorm
        
        do {
            try pipelineState = device?.makeRenderPipelineState(descriptor: pipelineDesc)
        }
        catch {
            print("Pipeline: Creating pipeline state failed")
        }
        
        
        let blurfragFunc = library?.makeFunction(name: "gaussianBlurFrag")
        
        let blurPipelineDesc = MTLRenderPipelineDescriptor()
        blurPipelineDesc.label = "GaussianBlur"
        blurPipelineDesc.vertexFunction = vertexFunc
        blurPipelineDesc.fragmentFunction = blurfragFunc
        blurPipelineDesc.colorAttachments[0].pixelFormat = MTLPixelFormat.bgra8Unorm
        
        do {
            try gaussianBlurPipelineState = device?.makeRenderPipelineState(descriptor: blurPipelineDesc)
        }
        catch {
            print("Pipeline: Creating pipeline state failed")
        }
    }
    
    func gaussianBlur(renderEncoder: MTLRenderCommandEncoder?, texture: MTLTexture?, sigma: Float) {
                
        var dir: float2
        
        renderEncoder?.pushDebugGroup("Gauassian Blur")
        renderEncoder?.setTriangleFillMode(.fill)
        renderEncoder?.setRenderPipelineState(gaussianBlurPipelineState!)

        renderEncoder?.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder?.setFragmentBytes(&viewportSize, length: MemoryLayout<float2>.stride, index: 0)
        renderEncoder?.setFragmentTexture(texture!, index: 0)

        dir = float2(sigma, 0)
        renderEncoder?.pushDebugGroup("Horizontal")
        renderEncoder?.setFragmentBytes(&dir, length: MemoryLayout<float2>.stride, index: 1)
        renderEncoder?.drawPrimitives(
            type: .triangle,
            vertexStart: 0,
            vertexCount: 6
        )
        renderEncoder?.popDebugGroup()

        renderEncoder?.pushDebugGroup("Vertical")

        dir = float2(0, sigma)
        renderEncoder?.setFragmentBytes(&dir, length: MemoryLayout<float2>.stride, index: 1)
        renderEncoder?.drawPrimitives(
            type: .triangle,
            vertexStart: 0,
            vertexCount: 6
        )
        renderEncoder?.popDebugGroup()

        renderEncoder?.popDebugGroup()
    }
    
    func draw(renderEncoder: MTLRenderCommandEncoder?, texture: MTLTexture?) {
        
        renderEncoder?.pushDebugGroup("Draw Fullscreen Quad")
        renderEncoder?.setRenderPipelineState(pipelineState!)
        renderEncoder?.setTriangleFillMode(.fill)
        
        renderEncoder?.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder?.setFragmentTexture(texture!, index: 0)
        
        renderEncoder?.drawPrimitives(
            type: .triangle,
            vertexStart: 0,
            vertexCount: 6
        )
        renderEncoder?.popDebugGroup()
    }
}
