//
//  Camera.swift
//  Athi
//
//  Created by Marcus Mathiassen on 04/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

struct Camera {
    
    var position = float3(0,0,0)
    var front = float3(0,0,-1)
    var up = float3(0,1,0)
    var right = float3()
    var worldUp = float3(0,1,0)
    
    var yaw: Float = -90
    var pitch: Float = 0
    
    var movementSpeed: Float = 4.5
    var mouseSensitivity: Float = 0.1
    var zoom: Float = 45
    
    var fov: Float = 45
    var aspectRatio: Float = 512/512
    var nearZ: Float = 0.1
    var farZ: Float = 1000.0
    var moveSpeed: Float = 0.02
    
    var viewMatrix = float4x4()
    var perspectiveProjection: float4x4
    var orthographicProjection: float4x4
}
