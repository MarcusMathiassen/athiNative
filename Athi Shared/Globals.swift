//
//  Globals.swift
//  Athi
//
//  Created by Marcus Mathiassen on 05/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

var pixelScale: Float = 0

var particleSize: Float = 5
var isMouseDown: Bool = false

var useMultihreading: Bool = false

var gyroRotation = float3(0,0,0)
var accelerometer = float3(0,0,0)

var viewportSize = float2(0,0)

#if os(macOS)
import AppKit
var backgroundColor = NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 1)
#else
import UIKit
var backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 1)
#endif
