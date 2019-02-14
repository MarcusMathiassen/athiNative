//
//  PrimitiveShapes.swift
//  Athi
//
//  Created by Marcus Mathiassen on 02/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

import MetalKit
import simd

class PrimitiveRenderer {
    
    var instanceCount = 0
    var allocatedCount = 1
    
    var indexBuffer: MTLBuffer

    var positionsBuffer: MTLBuffer! = nil
    var sizesBuffer: MTLBuffer! = nil
    var colorsBuffer: MTLBuffer! = nil

    var positions: [float2] = []
    var sizes: [float2] = []
    var colors: [float4] = []

    var device: MTLDevice
    var pipelineState: MTLRenderPipelineState?

    init(device: MTLDevice) {

        self.device = device

        let library = device.makeDefaultLibrary()!
        let vertexFunc = library.makeFunction(name: "basicVert")
        let fragFunc = library.makeFunction(name: "basicFrag")

        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.label = "PrimitiveRenderer"
        pipelineDesc.vertexFunction = vertexFunc
        pipelineDesc.fragmentFunction = fragFunc
        pipelineDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
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
            print("PrimitiveShapes Pipeline: Creating pipeline state failed")
        }

        positionsBuffer = device.makeBuffer(
            length: MemoryLayout<float2>.stride * allocatedCount,
            options: .storageModeShared)!

        sizesBuffer = device.makeBuffer(
            length: MemoryLayout<float2>.stride * allocatedCount,
            options: .storageModeShared)!

        colorsBuffer = device.makeBuffer(
            length: MemoryLayout<float4>.stride * allocatedCount,
            options: .storageModeShared)!

        let indices: [UInt16] = [0, 1, 2, 0, 2, 3]
        indexBuffer = device.makeBuffer(
            bytes: indices,
            length: MemoryLayout<UInt16>.stride * 6,
            options: .cpuCacheModeWriteCombined)!

    }
    
    func updateGPUBuffers() {
        
        // Check if we need to allocate more space on the buffers
        if instanceCount > allocatedCount {
            
            allocatedCount = instanceCount
            positionsBuffer = device.makeBuffer(length: MemoryLayout<float2>.stride * instanceCount, options: .storageModeShared)
            sizesBuffer = device.makeBuffer(length: MemoryLayout<float2>.stride * instanceCount, options: .storageModeShared)
            colorsBuffer = device.makeBuffer(length: MemoryLayout<float4>.stride * instanceCount, options: .storageModeShared)
        }
        
        positionsBuffer.contents().copyMemory(from: positions, byteCount: positionsBuffer.allocatedSize)
        sizesBuffer.contents().copyMemory(from: sizes, byteCount: sizesBuffer.allocatedSize)
        colorsBuffer.contents().copyMemory(from: colors, byteCount: colorsBuffer.allocatedSize)
    }

    func draw(view: MTKView, frameDescriptor: FrameDescriptor, commandBuffer: MTLCommandBuffer) {

        if instanceCount == 0 { return }
        
        let renderPassDesc = MTLRenderPassDescriptor()
        renderPassDesc.colorAttachments[0].texture = view.currentDrawable?.texture
        renderPassDesc.colorAttachments[0].loadAction = .clear
        renderPassDesc.colorAttachments[0].clearColor = frameDescriptor.clearColor

        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc)!
        renderEncoder.pushDebugGroup("Primitive Renderer Draw")
        
        renderEncoder.setRenderPipelineState(pipelineState!)
        renderEncoder.setTriangleFillMode(frameDescriptor.fillMode)
        
        updateGPUBuffers()
                
        renderEncoder.setVertexBuffers(
            [positionsBuffer, sizesBuffer, colorsBuffer],
            offsets: [0, 0, 0, 0],
            range: 0 ..< 3)
        
        renderEncoder.setVertexBytes(&viewportSize,
                                     length: MemoryLayout<float2>.stride,
                                     index: BufferIndex.bf_viewportSize_index.rawValue)
        
        renderEncoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: 6,
            indexType: .uint16,
            indexBuffer: indexBuffer,
            indexBufferOffset: 0,
            instanceCount: instanceCount
        )
        
        renderEncoder.popDebugGroup()
        renderEncoder.endEncoding()
    }
    

    /**
     Draws a rectangle at the position with the specified color and size.
     */
    public func drawRect(position: float2, color: float4, size: Float) {

        self.positions.append(position)
        self.colors.append(color)
        self.sizes.append(float2(size, size))

        instanceCount += 1
    }

    /**
     Draws a rectangle from min to max with the specified color.
     */
    public func drawRect(min: float2, max: float2, color: float4) {

        let width = max.x - min.x
        let height = max.y - min.y

        let position = float2(min.x + width/2, min.y + height/2)

        self.positions.append(position)
        self.sizes.append(float2(width/2, height/2))
        self.colors.append(color)

        instanceCount += 1
    }
    /**
     Draws a hollow circle at the position with the specified color and size.
     */
    public func drawHollowCircle(position: float2, color: float4, size: Float, borderWidth: Float = 1.0) {
    }

    /**
     Draws a rectangle at the position with the specified color and size.
     */
    public func drawHollowRect(position: float2, color: float4, size: Float, borderWidth: Float = 1.0) {

        // Draw a box with 4 rects as borders

        let bottomLeft      = float2(position.x - size, position.y - size)
        let bottomRight     = float2(position.x + size, position.y - size)
        let topLeft         = float2(position.x - size, position.y + size)
        let topRight        = float2(position.x + size, position.y + size)

        // Bottom
        drawRect(
            min: bottomLeft - float2(borderWidth, borderWidth),
            max: bottomRight + float2(borderWidth, borderWidth),
            color: color
        )

        // Left side
        drawRect(
            min: bottomLeft - float2(borderWidth, borderWidth),
            max: topLeft + float2(borderWidth, borderWidth),
            color: color
        )

        // Top
        drawRect(
            min: topLeft - float2(borderWidth, borderWidth),
            max: topRight + float2(borderWidth, borderWidth),
            color: color
        )

        // Right side
        drawRect(
            min: bottomRight - float2(borderWidth, borderWidth),
            max: topRight + float2(borderWidth, borderWidth),
            color: color
        )
    }

    /**
     Draws a rectangle at the position with the specified color and size.
     */
    public func drawHollowRect(min: float2, max: float2, color: float4, borderWidth: Float = 1.0) {

        // Draw a box with 4 rects as borders

        let bottomLeft      = min
        let bottomRight     = float2(max.x, min.y)
        let topLeft         = float2(min.x, max.y)
        let topRight        = max

        // Bottom
        drawRect(
            min: bottomLeft - float2(borderWidth, borderWidth),
            max: bottomRight + float2(borderWidth, borderWidth),
            color: color
        )

        // Left side
        drawRect(
            min: bottomLeft - float2(borderWidth, borderWidth),
            max: topLeft + float2(borderWidth, borderWidth),
            color: color
        )

        // Top
        drawRect(
            min: topLeft - float2(borderWidth, borderWidth),
            max: topRight + float2(borderWidth, borderWidth),
            color: color
        )

        // Right side
        drawRect(
            min: bottomRight - float2(borderWidth, borderWidth),
            max: topRight + float2(borderWidth, borderWidth),
            color: color
        )
    }
}
