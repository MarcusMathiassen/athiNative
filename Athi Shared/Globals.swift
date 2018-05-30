//
//  Globals.swift
//  Athi
//
//  Created by Marcus Mathiassen on 05/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

let kGravitationalConstant = 6.67408e-6

enum ComputeDeviceOption {
    case cpu
    case gpu
}

enum TreeOption {
    case quadtree
    case noTree
}

var gBlurStrength: Float = 5.0
var gLifetime: Float = 1.0
var gSpeed: Float = 1.0
var gParticleCount: Int = 10

var gSpawnAmount: Int = 10
var gComputeDeviceOption: ComputeDeviceOption = .cpu
var gTreeOption: TreeOption = .quadtree
var gDrawDebug: Bool = false

var gPixelScale: Float = 0

var gParticleSize: Float = 4

var gParticleColorCycle: Bool = false
var gParticleColor: float4 = float4(1)

var gyroRotation = float3(0, 0, 0)
var accelerometer = float3(0, 0, 0)

var viewportSize = float2(0, 0)

#if os(macOS)
    import AppKit
    var backgroundColor = NSColor(calibratedRed: 9/255, green: 9/255, blue: 9/255, alpha: 1)

    var colorSpace: NSColorSpace?
#else
    import UIKit
    var backgroundColor = UIColor(red: 9/255, green: 9/255, blue: 9/255, alpha: 1)
#endif
