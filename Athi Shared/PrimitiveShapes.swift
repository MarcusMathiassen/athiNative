//
//  PrimitiveShapes.swift
//  Athi
//
//  Created by Marcus Mathiassen on 02/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

import simd
import MetalKit

class PrimitiveRenderer {
    
    struct Vertex {
        var position: float2
        var color: float4
    }
    
    struct Uniform {
        var modelMatrix: float4x4
    }
    
    var uniforms: [float4x4] = []
    var vertices: [Vertex] = []
    var vertexBuffer: MTLBuffer?
    var uniformBuffer: MTLBuffer?
    
    var device: MTLDevice?
    var pipelineState: MTLRenderPipelineState?

    init(device: MTLDevice?) {
        self.device = device
        
        let library = device?.makeDefaultLibrary()!
        let vertexFunc = library?.makeFunction(name: "basicVert")
        let fragFunc = library?.makeFunction(name: "basicFrag")
        
        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.label = "PrimitiveRenderer"
        pipelineDesc.vertexFunction = vertexFunc
        pipelineDesc.fragmentFunction = fragFunc
        pipelineDesc.colorAttachments[0].pixelFormat = MTLPixelFormat.bgra8Unorm_srgb
        
        do {
            try pipelineState = device?.makeRenderPipelineState(descriptor: pipelineDesc)
        }
        catch {
            print("PrimitiveShapes Pipeline: Creating pipeline state failed")
        }
    }
    
    func draw(renderEncoder: MTLRenderCommandEncoder?, vp: float4x4) {
        if vertices.count == 0 { return }
        
        renderEncoder?.label = "PrimitiveShapes"
        renderEncoder?.setRenderPipelineState(pipelineState!)
        
        vertexBuffer = device?.makeBuffer(bytes: vertices, length: MemoryLayout<Vertex>.stride * vertices.count, options: .cpuCacheModeWriteCombined)
        uniformBuffer = device?.makeBuffer(bytes: uniforms, length: MemoryLayout<float4x4>.stride * uniforms.count, options: .cpuCacheModeWriteCombined)
        
        renderEncoder?.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder?.setVertexBuffer(uniformBuffer, offset: 0, index: 1)

        renderEncoder?.drawPrimitives(
            type: .triangle,
            vertexStart: 0,
            vertexCount: vertices.count
        )
        
        vertices.removeAll()
        uniforms.removeAll()
    }
    
    
    private func addTransform(_ transform: Transform) {
        let ortho = makeOrtho(left: 0, right: framebufferWidth, bottom: 0, top: framebufferHeight, near: -1, far: 1)
        
        let model = ortho * transform.getModel()
        self.uniforms.append(model)
    }
    
    private func addVertices(vertices: [Float]) {
        for i in stride(from: 0, to: vertices.count, by: 6) {
            let vert = Vertex(position: float2(vertices[i+0], vertices[i+1]), color: float4(vertices[i+2], vertices[i+3], vertices[i+4], vertices[i+5]))
            self.vertices.append(vert)
        }
    }
    
    private func updateVertexBuffer() {
        vertexBuffer = device?.makeBuffer(bytes: vertices, length: MemoryLayout<Vertex>.stride * vertices.count, options: .cpuCacheModeWriteCombined)
    }
    
    
    /**
     Draws a triangle at the position with the specified color and size.
     */
    public func drawTriangle(position: float2, color: float4, size: Float) {
        addVertices(vertices: [
            -1.0, -1.0,   color.x, color.y, color.z, color.w,
            0.0,  1.0,   color.x, color.y, color.z, color.w,
            1.0, -1.0,   color.x, color.y, color.z, color.w,
            ])
        
        var trans = Transform()
        trans.pos = float3(position.x, position.y, 1)
        trans.scale *= size
        
        addTransform(trans)
    }
    
    /**
     Draws a rectangle at the position with the specified color and size.
     */
    public func drawRect(position: float2, color: float4, size: Float) {
        addVertices(vertices: [
            -1.0,  1.0,    color.x, color.y, color.z, color.w,
            1.0,  1.0,    color.x, color.y, color.z, color.w,
            1.0, -1.0,    color.x, color.y, color.z, color.w,
            
            -1.0,  1.0,    color.x, color.y, color.z, color.w,
            1.0, -1.0,    color.x, color.y, color.z, color.w,
            -1.0, -1.0,    color.x, color.y, color.z, color.w,
            ])
        
        var trans = Transform()
        trans.pos = float3(position.x, position.y, 0)
        trans.scale *= size
        
        addTransform(trans)
    }
    
    /**
     Draws a rectangle from min to max with the specified color.
     */
    public func drawRect(min: float2, max: float2, color: float4) {
        addVertices(vertices: [
            -1.0,   1.0,    color.x, color.y, color.z, color.w,
            1.0,   1.0,    color.x, color.y, color.z, color.w,
            1.0,  -1.0,    color.x, color.y, color.z, color.w,
            
            -1.0,   1.0,    color.x, color.y, color.z, color.w,
            1.0,  -1.0,    color.x, color.y, color.z, color.w,
            -1.0,  -1.0,    color.x, color.y, color.z, color.w,
            ])
        
        let width = max.x - min.x
        let height = max.y - min.y
        
        var trans = Transform()
        trans.pos = float3(min.x+width/2, min.y+height/2, 1)
        trans.scale.x *= width;
        trans.scale.y *= height;
        
        addTransform(trans)
    }
    
    /**
     Draws a point at the given position with the specified color, size and vertexCount
     */
    public func drawPoint(center: float2, color: float4, radius: Float, vertexCount: Int) {
        
        // Since each vertex consists of 3 points.
        let n_vertices = vertexCount * 3;
        
        // Setup the particle vertices
        var verts: [Float] = []
        
        // Start out by setting the last inserted vertex to our center
        var last_vert = center
        
        var k = 0
        for i in 0..<n_vertices+3 {
            
            // Pos
            switch k
            {
            case 0:
                k += 1
                verts.append(last_vert.x)
                verts.append(last_vert.y)
            case 1:
                k += 1
                let cont =  Float(i-1) * Float.pi * 2 / Float(n_vertices)
                let x = cos(cont)
                let y = sin(cont)
                last_vert = float2(center.x * x, center.y * y)
                verts.append(last_vert.x)
                verts.append(last_vert.y)
            case 2:
                k += 1
                k = 0
                verts.append(center.x)
                verts.append(center.y)
            default:
                k = 0
            }
            
            // Color
            verts.append(color.x)
            verts.append(color.y)
            verts.append(color.z)
            verts.append(color.w)
        }
        
        addVertices(vertices: verts)
        
        var trans = Transform()
        trans.pos = float3(center.x, center.y, 0)
        trans.scale *= radius
        
        addTransform(trans)
    }
    
    
    public func drawHalfPoint(center: float2, color: float4, radius: Float, angle: Float, numVertex: Int) {
        // Since each vertex consists of 3 points.
        let n_vertices = numVertex * 3;
        
        // Setup the particle vertices
        var verts: [Float] = []
        
        // Start out by setting the last inserted vertex to our center
        var last_vert = center
        
        var k = 0;
        for i in 0..<n_vertices+3 {
            
            // Pos
            switch k
            {
            case 0:
                k += 1
                verts.append(last_vert.x)
                verts.append(last_vert.y)
            case 1:
                k += 1
                let cont = angle+Float(i-1) * Float.pi / Float(n_vertices)
                let x = cos(cont)
                let y = sin(cont)
                last_vert = float2(center.x + radius * x, center.y + radius * y)
                verts.append(last_vert.x)
                verts.append(last_vert.y)
            case 2:
                k = 0
                verts.append(center.x)
                verts.append(center.y)
            default:
                k = 0
            }
            
            // Color
            verts.append(color.x)
            verts.append(color.y)
            verts.append(color.z)
            verts.append(color.w)
        }
        
        addVertices(vertices: verts)
    }
    
    public func drawLine(p1: float2, p2: float2, color: float4, size: Float) {
        
        // Dont draw anything with negative size.
        if size < 0.0 { return }
        
        // Get the distance between our two points
        let d = distance(p1, p2) / 2.0
        
        let dx = (p2.x - p1.x)
        let dy = (p2.y - p1.y)
        
        // Get the angle between our two points (radians)
        let theta = atan2(dy, dx)
        
        // Draw the end caps
        drawHalfPoint(center: p1, color: color, radius: size, angle: theta+Float.pi/2, numVertex: 12)
        drawHalfPoint(center: p2, color: color, radius: size, angle: theta-Float.pi/2, numVertex: 12)
        
        // We draw the line as a rotated rect. So we place a
        // rect with the correct size horizontal in the middle between both points
        // and rotate it at that point by our angle.
        
        let center = (p1+p2) * 0.5
        let bot = float2(center.x-d+size, center.y)
        let top = float2(center.x+d-size, center.y)
        
        // Rotate
        let min = float2(bot.x-size, bot.y-size)
        let max = float2(top.x+size, top.y+size)
        
        var pos: [float2] = [
            float2(min.x,  max.y),
            float2(max.x,  max.y),
            float2(max.x,  min.y),
            
            float2(min.x,  max.y),
            float2(max.x,  min.y),
            float2(min.x,  min.y)
        ]
        
        for i in 0...pos.count-1 {
            // cx, cy - center of square coordinates
            // x, y - coordinates of a corner point of the square
            // theta is the angle of rotation
            
            // translate point to origin
            let temp_x = pos[i].x - center.x;
            let temp_y = pos[i].y - center.y;
            
            // now apply rotation
            let rotated_x = temp_x * cos(theta) - temp_y * sin(theta);
            let rotated_y = temp_x * sin(theta) + temp_y * cos(theta);
            
            // translate back
            pos[i].x = rotated_x + center.x;
            pos[i].y = rotated_y + center.y;
        }
        addVertices(vertices: [
            pos[0].x,  pos[0].y, color.x, color.y, color.z, color.w,
            pos[1].x,  pos[1].y, color.x, color.y, color.z, color.w,
            pos[2].x,  pos[2].y, color.x, color.y, color.z, color.w,
            
            pos[3].x,  pos[3].y, color.x, color.y, color.z, color.w,
            pos[4].x,  pos[4].y, color.x, color.y, color.z, color.w,
            pos[5].x,  pos[5].y, color.x, color.y, color.z, color.w,
            ])
    }

}
