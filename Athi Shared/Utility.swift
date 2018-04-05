//
//  Utility.swift
//  Athi
//
//  Created by Marcus Mathiassen on 02/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Darwin // arc4random
import simd // float2, float3, float4, etc

/**
 High resolution clock: return the current time in milliseconds
 */
func getTime() -> Double {
    var info = mach_timebase_info()
    guard mach_timebase_info(&info) == KERN_SUCCESS else { return -1 }
    let currentTime = mach_absolute_time()
    let nanos = currentTime * UInt64(info.numer) / UInt64(info.denom)
    
    return Double(nanos) / 1_000_000_000
}

/**
 Return the current point in viewspace
*/
func toViewspace(_ point: float2) -> float2 {
    var w = point;
    w.x = -1.0 + 2 * point.x / viewport.x
    w.y =  1.0 - 2 * point.y / viewport.y
    w.y *= -1
    return w;
}

func getBeginAndEnd(i: Int, containerSize: Int, segments: Int) -> (Int, Int) {
    let parts = containerSize / segments
    let leftovers = containerSize % segments
    let begin = parts * i
    var end = parts * (i + 1)
    if i == segments - 1 { end += leftovers }
    return (begin, end)
}

/**
    Returns a random float between min and max
*/
func randFloat(_ min: Float, _ max: Float) -> Float {
    return ((Float(arc4random()) / Float(UINT32_MAX)) * (max - min)) + min
}

/**
    Returns a random float2 between min and max
*/
func randFloat2(_ min: Float, _ max: Float) -> float2 {
  return float2(randFloat(min, max), randFloat(min, max));
}

/**
    Returns a random float3 between min and max
*/
func randFloat3(_ min: Float, _ max: Float) -> float3 {
  return float3(randFloat(min, max), randFloat(min, max), randFloat(min, max));
}

/**
    Returns a random float4 between min and max
*/
func randFloat4(_ min: Float, _ max: Float) -> float4 {
  return float4(randFloat(min, max), randFloat(min, max), randFloat(min, max), randFloat(min, max));
}



func hsv2rgb(_ h: Int, _ s: Float, _ v: Float, _ a: Float) -> float4 {
    
    // gray
    if (s == 0.0) { return float4(v, v, v, a) }

    let th = Float((h >= 360) ? 0 : h)
    let hue: Float = th * 1.0 / 60.0


    // Converts HSV to a RGB color
    var r: Float
    var g: Float
    var b: Float

    let i = Int(hue * 6)
    let f = Float(hue) * 6 - Float(i)
    let p = v * (1 - s)
    let q = v * (1 - f * s)
    let t = v * (1 - (1 - f) * s)
    
    switch (i % 6) {
        case 0: r = v; g = t; b = p; break;
        
        case 1: r = q; g = v; b = p; break;
        
        case 2: r = p; g = v; b = t; break;
        
        case 3: r = p; g = q; b = v; break;
        
        case 4: r = t; g = p; b = v; break;
        
        case 5: r = v; g = p; b = q; break;
        
        default: r = v; g = t; b = p;
    }

    return float4(r,g,b,a)
}

/**
    Returns the RGBA ekvivalent of the HSV input
*/
func HSVtoRGBA(_ h: Int, _ s: Float, _ v: Float, _ a: Float) -> float4
{
  // gray
  if (s == 0.0) { return float4(v, v, v, a) }

  let th = Float((h >= 360) ? 0 : h)
  let hue: Float = th * 1.0 / 60.0

  let i: Int = Int(hue)
  let f: Float = hue - Float(i)
  let p: Float = v * (1.0 - s)
  let q: Float = v * (1.0 - s * f)
  let t: Float = v * (1.0 - s * (1.0 - f))

    var r: Float = 0, g: Float = 0, b: Float = 0

  switch i {
    case 0: r = v; g = t; b = p
    case 1: r = q; g = v; b = p
    case 2: r = p; g = v; b = t
    case 3: r = p; g = q; b = v
    case 4: r = t; g = p; b = v
    case 5: r = b; g = p; b = q
    default: r = v; g = p; b = q
  }
    
  return float4(r, g, b, a)
}

/**
    Returns the HSV ekvivalent of the RGBA input
*/
func RGBAtoHSV(_ rgba: float4) -> float4 {
    var out = float4()

    var min: Float = 0.0
    var max: Float = 0.0
    var delta: Float = 0.0

    min = rgba.x < rgba.y ? rgba.x : rgba.y
    min = min < rgba.z ? min : rgba.z

    max = rgba.x > rgba.y ? rgba.x : rgba.y
    max = max > rgba.z ? max : rgba.z

    out.z = max  // v

    out.w = rgba.w

    delta = max - min;
    if delta < 0.00001 {
      out.y = 0
      out.x = 0  // undefined, maybe nan?
      return out
    }
    if max > 0.0 {  // NOTE: if Max is == 0, this divide would cause a crash
      out.y = (delta / max)  // s
    } else {
        // if max is 0, then r = g = b = 0
        // s = 0, h is undefined
        out.y = 0.0
        out.x = Float(FP_NAN)  // its now undefined
        return out
    }

    if rgba.x >= max {  // > is bogus, just keeps compilor happy
      out.x = (rgba.y - rgba.z) / delta  // between yellow & magenta
    }
    else if rgba.y >= max {
      out.x = 2.0 + (rgba.z - rgba.x) / delta  // between cyan & yellow
    }
    else {
      out.x = 4.0 + (rgba.x - rgba.y) / delta  // between magenta & cyan
    }
    out.x *= 60.0                          // degrees
    if (out.x < 0.0)  { out.x += 360.0 }
    
    return out
}

func lerpHSV(a: float4, b: float4, t: Float) -> float4 {
    
    var A = a
    var B = b
    var T = t
    
    // Hue interpolation
    var h: Float = 0
    var d = B.x - A.x
    if A.x > B.x {
      swap(&A.x, &B.x)

      d = -d
      T = 1 - T
    }

    if d > 0.5 { // 180deg 
      A.x = A.x + 1                // 360deg
      h = (A.x + T * (B.x - A.x))  // 360deg
    }
    if (d <= 0.5) {  // 180deg
      h = A.x + T * d
    }

    h = h > 360 ? 360 : h < 0 ? 0 : h

    // Interpolates the rest
    return float4(h,                    // H
                A.y + T * (B.y - A.y),  // S
                A.z + T * (B.z - A.z),  // V
                A.w + T * (B.w - A.w)   // A
    );
}

func colorOverTime(_ time: Double) -> float4 {
    let T = abs(sinf(Float(time)))
    #if os(macOS)
    let rgba = NSColor(calibratedHue: CGFloat(T), saturation: 1, brightness: 1, alpha: 1)
    let r = rgba.redComponent
    let g = rgba.greenComponent
    let b = rgba.blueComponent
    #else
    let rgba = UIColor(hue: CGFloat(T), saturation: 1, brightness: 1, alpha: 1)
    let r = rgba.cgColor.components![0]
    let g = rgba.cgColor.components![1]
    let b = rgba.cgColor.components![2]
    #endif
    return float4(Float(r), Float(g), Float(b), 1)
}
