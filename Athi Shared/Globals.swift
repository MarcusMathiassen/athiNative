//
//  Globals.swift
//  Athi
//
//  Created by Marcus Mathiassen on 05/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

let kGravitationalConstant = 6.67408e-6

var gComputeDeviceOption: ComputeDeviceOption = .cpu
var gTreeOption: TreeOption = .quadtree
var gDrawDebug: Bool = false

var pixelScale: Float = 0

var particleSize: Float = 4

var particleColorCycle: Bool = true

var gyroRotation = float3(0, 0, 0)
var accelerometer = float3(0, 0, 0)

var viewportSize = float2(0, 0)

#if os(macOS)
    import AppKit
    var backgroundColor = NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 1)

    var colorSpace: NSColorSpace?
#else
    import UIKit
    var backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 1)
#endif
