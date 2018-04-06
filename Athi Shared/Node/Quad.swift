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
    
    var texture: MTLTexture?
    
    
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
        pipelineDesc.sampleCount = 4
        pipelineDesc.colorAttachments[0].isBlendingEnabled = true
        pipelineDesc.colorAttachments[0].rgbBlendOperation = .add
        pipelineDesc.colorAttachments[0].alphaBlendOperation = .add
        pipelineDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDesc.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        pipelineDesc.colorAttachments[0].destinationRGBBlendFactor = .destinationAlpha
        pipelineDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        pipelineDesc.colorAttachments[0].pixelFormat = MTLPixelFormat.bgra8Unorm_srgb
        
        do {
            try pipelineState = device?.makeRenderPipelineState(descriptor: pipelineDesc)
        }
        catch {
            print("ParticleSystem Pipeline: Creating pipeline state failed")
        }
    }
    
    func draw(renderEncoder: MTLRenderCommandEncoder?, texture: MTLTexture?, direction: float2) {
        
        renderEncoder?.pushDebugGroup("Draw Fullscreen Quad")
        renderEncoder?.setRenderPipelineState(pipelineState!)
        renderEncoder?.setTriangleFillMode(.fill)

        var dir = direction
        renderEncoder?.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder?.setFragmentBytes(&viewportSize, length: MemoryLayout<float2>.stride, index: 0)
        renderEncoder?.setFragmentBytes(&dir, length: MemoryLayout<float2>.stride, index: 1)
        
        renderEncoder?.setFragmentTexture(texture!, index: 0)
        
        renderEncoder?.drawPrimitives(
            type: .triangle,
            vertexStart: 0,
            vertexCount: 6
        )
        renderEncoder?.popDebugGroup()
    }
}
