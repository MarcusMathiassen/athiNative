//
//  Triangle.swift
//  Athi
//
//  Created by Marcus Mathiassen on 04/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

import MetalKit

class Triangle: Entity {
    
    var vel = float2(0)
    
    let positions: [float2] = [
        float2(-1, -1),
        float2( 0,  1),
        float2( 1, -1),
    ]
    
    let colors: [float4] = [
        float4( 1,  0, 0, 1),
        float4( 0,  1, 0, 1),
        float4( 0,  0, 1, 1),
    ]

    var transform = Transform()
    
    var pipelineState: MTLRenderPipelineState?
    
    init(device: MTLDevice?) {
    
        let library = device?.makeDefaultLibrary()!
        let vertexFunc = library?.makeFunction(name: "vertex_main")
        let fragFunc = library?.makeFunction(name: "fragment_main")
        
        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.label = "Triangle Pipeline"
        pipelineDesc.vertexFunction = vertexFunc
        pipelineDesc.fragmentFunction = fragFunc
        pipelineDesc.sampleCount = 4
        pipelineDesc.colorAttachments[0].pixelFormat = MTLPixelFormat.bgra8Unorm_srgb
        
        do {
            try pipelineState = device?.makeRenderPipelineState(descriptor: pipelineDesc)
        }
        catch {
            print("Triangle Pipeline: Creating pipeline state failed")
        }
    }
    
    override func update() {
        
        vel.x += 1

        vel.y += -9.81
        transform.pos += float3(vel.x, vel.y, 0)
        
        if transform.pos.x < 0 { transform.pos.x = 0; vel.x -= -1}
        if transform.pos.x > screenWidth { transform.pos.x = screenWidth ; vel.x *= -1}
        if transform.pos.y < 0 { transform.pos.y = 0 ; vel.y *= -1}
        if transform.pos.y > screenHeight { transform.pos.y = screenHeight ; vel.y *= -1}
    }
    
    override func draw(renderEncoder: MTLRenderCommandEncoder?, vp: float4x4) {
        
        renderEncoder?.label = "Triangle"
        renderEncoder?.setRenderPipelineState(pipelineState!)
        
        var mvp = vp * transform.getModel()
        
        let positionsSize = positions.count * MemoryLayout.stride(ofValue: positions)
        let colorsSize = colors.count * MemoryLayout.stride(ofValue: colors)
        let mvpSize = MemoryLayout.size(ofValue: mvp)
        
        renderEncoder?.setVertexBytes(positions, length: positionsSize, index: 0)
        renderEncoder?.setVertexBytes(colors, length: colorsSize, index: 1)
        
        renderEncoder?.setVertexBytes(&mvp, length: mvpSize, index: 2)
        
        renderEncoder?.drawPrimitives(
            type: .triangle,
            vertexStart: 0,
            vertexCount: positions.count)
        
    }
}
