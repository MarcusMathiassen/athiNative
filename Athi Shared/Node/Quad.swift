//
//  Quad.swift
//  Athi
//
//  Created by Marcus Mathiassen on 05/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

import MetalKit

final class Quad {
    var device: MTLDevice
    var pipelineState: MTLRenderPipelineState?
    var gaussianBlurPipelineState: MTLRenderPipelineState?

    // Compute
    var pixelateComputePipelineState: MTLComputePipelineState?
    var mixComputePipelineState: MTLComputePipelineState?

    init(device: MTLDevice) {
        self.device = device

        let library = device.makeDefaultLibrary()!
        let vertexFunc = library.makeFunction(name: "quadVert")
        let fragFunc = library.makeFunction(name: "quadFrag")

        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.label = "Quad"
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
            print("Pipeline: Creating pipeline state failed")
        }

        let blurfragFunc = library.makeFunction(name: "gaussianBlurFrag")

        let blurPipelineDesc = MTLRenderPipelineDescriptor()
        blurPipelineDesc.label = "GaussianBlur"
        blurPipelineDesc.vertexFunction = vertexFunc
        blurPipelineDesc.fragmentFunction = blurfragFunc
        blurPipelineDesc.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            try gaussianBlurPipelineState = device.makeRenderPipelineState(descriptor: blurPipelineDesc)
        } catch {
            print("Pipeline: Creating pipeline state failed")
        }

        // Load the kernel function from the library
        let pixelateComputeFunc = library.makeFunction(name: "pixelate")

        // Create a compute pipeline state
        do {
            try pixelateComputePipelineState = device.makeComputePipelineState(function: pixelateComputeFunc!)
        } catch {
            print("Pipeline: Creating pipeline state failed")
        }

        // Load the kernel function from the library
        let mixComputeFunc = library.makeFunction(name: "mix")

        // Create a compute pipeline state
        do {
            try mixComputePipelineState = device.makeComputePipelineState(function: mixComputeFunc!)
        } catch {
            print("Pipeline: Creating pipeline state failed")
        }
    }

    func mix(
        commandBuffer: MTLCommandBuffer,
        inputTexture1: MTLTexture,
        inputTexture2: MTLTexture,
        outTexture: MTLTexture,
        sigma: Float) {

        // Compute kernel threadgroup size
        let threadExecutionWidth = (mixComputePipelineState?.threadExecutionWidth)!
        let maxTotalThreadsPerThreadgroup =
            (mixComputePipelineState?.maxTotalThreadsPerThreadgroup)! / threadExecutionWidth

        // Make the encoder
        let computeEncoder = commandBuffer.makeComputeCommandEncoder()

        // Set the pipelinestate
        computeEncoder?.setComputePipelineState(mixComputePipelineState!)

//         Set the textures
        computeEncoder?.setTextures([inputTexture1, inputTexture2, outTexture], range: 0 ..< 3)

        // Set thread groups
        #if os(macOS)
        let threadsPerThreadGroup = MTLSize(
            width: threadExecutionWidth,
            height: maxTotalThreadsPerThreadgroup,
            depth: 1)
        let threadPerGrid = MTLSize(width: inputTexture1.width, height: inputTexture1.height, depth: 1)
        computeEncoder?.dispatchThreads(threadPerGrid, threadsPerThreadgroup: threadsPerThreadGroup)
        #else
        let tSize = MTLSize(width: 16, height: 16, depth: 1)
        let tCount = MTLSize(
            width: (inputTexture1.width + tSize.width - 1) / tSize.width,
            height: (inputTexture1.height + tSize.height - 1) / tSize.height,
            depth: 1)
        computeEncoder?.dispatchThreadgroups(tCount, threadsPerThreadgroup: tSize)
        #endif

        // Finish
        computeEncoder?.endEncoding()
    }

    func pixelate(
        commandBuffer: MTLCommandBuffer,
        inputTexture: MTLTexture,
        outputTexture: MTLTexture,
        sigma: Float)
    {
        // Compute kernel threadgroup size
        let threadExecutionWidth = (pixelateComputePipelineState?.threadExecutionWidth)!
        let maxTotalThreadsPerThreadgroup =
            (pixelateComputePipelineState?.maxTotalThreadsPerThreadgroup)! / threadExecutionWidth

        // Make the encoder
        let computeEncoder = commandBuffer.makeComputeCommandEncoder()

        // Set the pipelinestate
        computeEncoder?.setComputePipelineState(pixelateComputePipelineState!)

        // Set the textures
        computeEncoder?.setTextures([inputTexture, outputTexture], range: 0 ..< 2)

        var pixSigma = sigma
        computeEncoder?.setBytes(&pixSigma, length: MemoryLayout<Float>.stride, index: 0)

        // Set thread groups
        #if os(macOS)
        let threadsPerThreadGroup = MTLSize(
            width: threadExecutionWidth,
            height: maxTotalThreadsPerThreadgroup,
            depth: 1)
        let threadPerGrid = MTLSize(width: inputTexture.width, height: inputTexture.height, depth: 1)
        computeEncoder?.dispatchThreads(threadPerGrid, threadsPerThreadgroup: threadsPerThreadGroup)
        #else
        let tSize = MTLSize(width: 16, height: 16, depth: 1)
        let tCount = MTLSize(
            width: (inputTexture.width + tSize.width - 1) / tSize.width,
            height: (inputTexture.height + tSize.height - 1) / tSize.height,
            depth: 1)
        computeEncoder?.dispatchThreadgroups(tCount, threadsPerThreadgroup: tSize)
        #endif
        // Finish
        computeEncoder?.endEncoding()
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

    func draw(renderEncoder: MTLRenderCommandEncoder, texture: MTLTexture) {
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
