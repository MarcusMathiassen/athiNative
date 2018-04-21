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

    var indexBuffer: MTLBuffer
    
    var positionsBuffer: MTLBuffer
    var colorsBuffer: MTLBuffer
    var sizesBuffer: MTLBuffer

    var positions: [float2] = []
    var sizes: [float2] = []
    var colors: [float4] = []

    var rectCount = 0
    var rectsAllocatedCount = 0

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
        pipelineDesc.colorAttachments[0].pixelFormat = MTLPixelFormat.bgra8Unorm_srgb
        
        do {
            try pipelineState = device.makeRenderPipelineState(descriptor: pipelineDesc)
        } catch {
            print("PrimitiveShapes Pipeline: Creating pipeline state failed")
        }

        positionsBuffer = device.makeBuffer(
            length: MemoryLayout<float2>.stride,
            options: .storageModeShared)!

        sizesBuffer = device.makeBuffer(
            length: MemoryLayout<float2>.stride,
            options: .storageModeShared)!

        colorsBuffer = device.makeBuffer(
            length: MemoryLayout<float4>.stride,
            options: .storageModeShared)!
        
        let indices: [UInt16] = [0,1,2, 0,2,3]
        indexBuffer = device.makeBuffer(
            bytes: indices,
            length: MemoryLayout<UInt16>.stride * 6,
            options: .cpuCacheModeWriteCombined)!

    }

    func draw(
        view: MTKView,
        frameDescriptor: FrameDescriptor,
        commandBuffer: MTLCommandBuffer
        ) {

        if rectCount == 0 { return }

        commandBuffer.pushDebugGroup("PrimitiveRenderer Draw")

        let renderPassDesc = view.currentRenderPassDescriptor
        renderPassDesc?.colorAttachments[0].loadAction = .load
        
        if renderPassDesc != nil {

            let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc!)!

            renderEncoder.pushDebugGroup("Draw primitives")

            renderEncoder.setRenderPipelineState(pipelineState!)
            renderEncoder.setTriangleFillMode(frameDescriptor.fillMode)

            renderEncoder.label = "PrimitiveShapes"
            renderEncoder.setRenderPipelineState(pipelineState!)

            renderEncoder.setVertexBytes(&viewportSize,
                                         length: MemoryLayout<float2>.stride,
                                         index: BufferIndex.ViewportSizeIndex.rawValue)

            updateGPUBuffers(commandBuffer: commandBuffer)

            renderEncoder.setVertexBuffer(positionsBuffer, offset: 0, index: BufferIndex.PositionIndex.rawValue)
            renderEncoder.setVertexBuffer(sizesBuffer, offset: 0, index: BufferIndex.SizeIndex.rawValue)
            renderEncoder.setVertexBuffer(colorsBuffer, offset: 0, index: BufferIndex.ColorIndex.rawValue)

            renderEncoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: 6,
                indexType: .uint16,
                indexBuffer: indexBuffer,
                indexBufferOffset: 0,
                instanceCount: rectCount
            )

            renderEncoder.endEncoding()

            positions.removeAll()
            sizes.removeAll()
            colors.removeAll()

            rectCount = 0
            rectsAllocatedCount = 0
        }
    }

    private func updateGPUBuffers(commandBuffer: MTLCommandBuffer) {

        // Reallocate more if needed
        if rectCount > rectsAllocatedCount {

            // Update the allocated particle count
            rectsAllocatedCount = rectCount

            // Update the size of the GPU buffers
            positionsBuffer = device.makeBuffer(
                length: rectsAllocatedCount * MemoryLayout<float2>.stride,
                options: .storageModeShared)!

            sizesBuffer = device.makeBuffer(
                length: rectsAllocatedCount * MemoryLayout<float2>.stride,
                options: .storageModeShared)!

            colorsBuffer = device.makeBuffer(
                length: rectsAllocatedCount * MemoryLayout<float4>.stride,
                options: .storageModeShared)!
        }

        positionsBuffer.contents().copyMemory(
            from: &positions,
            byteCount: rectsAllocatedCount * MemoryLayout<float2>.stride)

        sizesBuffer.contents().copyMemory(
            from: &sizes,
            byteCount: rectsAllocatedCount * MemoryLayout<float2>.stride)

        colorsBuffer.contents().copyMemory(
            from: &colors,
            byteCount: rectsAllocatedCount * MemoryLayout<float4>.stride)

    }

    /**
     Draws a rectangle at the position with the specified color and size.
     */
    public func drawRect(position: float2, color: float4, size: Float) {

        self.positions.append(position)
        self.colors.append(color)
        self.sizes.append(float2(size, size))

        rectCount = positions.count
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

        rectCount = positions.count
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
