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
import Accelerate.vImage

// swiftlint:disable identifier_name

func float32tofloat16(_ input: Float32) -> UInt16 {
    var ink = input
    var value: UInt16 = 0
    var bufferFloat32 = vImage_Buffer(data: &ink, height: 1, width: 1, rowBytes: 4)
    var bufferFloat16 = vImage_Buffer(data: &value, height: 1, width: 1, rowBytes: 2)
    
    if vImageConvert_PlanarFtoPlanar16F(&bufferFloat32, &bufferFloat16, 0) != kvImageNoError {
        print("Error converting float32 to float16")
    }
    return value
}

struct half4 {
//    var data: [UInt16] = [0, 0, 0, 0]
    var x: UInt16
    var y: UInt16
    var z: UInt16
    var w: UInt16
    
    init(_ x: Float32, _ y: Float32, _ z: Float32, _ w: Float32) {
        self.x = float32tofloat16(x)
        self.y = float32tofloat16(y)
        self.z = float32tofloat16(z)
        self.w = float32tofloat16(w)
//        data[0] = float32tofloat16(x)
//        data[1] = float32tofloat16(y)
//        data[2] = float32tofloat16(z)
//        data[3] = float32tofloat16(w)
    }
    
    init(_ v: float4) {
        
        self.x = float32tofloat16(v.x)
        self.y = float32tofloat16(v.y)
        self.z = float32tofloat16(v.z)
        self.w = float32tofloat16(v.w)
//
//        data[0] = float32tofloat16(v.x)
//        data[1] = float32tofloat16(v.y)
//        data[2] = float32tofloat16(v.z)
//        data[3] = float32tofloat16(v.w)
    }
}

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
    var w = point
    w.x = -1.0 + 2 * point.x / viewport.x
    w.y = 1.0 - 2 * point.y / viewport.y
    w.y *= -1
    return w
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
 Returns the minimum and maximum position found
 */
func getMinAndMaxPosition(positions: [float2], count: Int) -> (float2, float2) {

    var max = float2(Float((-INT_MAX)), Float(-INT_MAX))
    var min = float2(Float(INT_MAX), Float(INT_MAX))

    for i in 0 ..< count {

        let pos = positions[i]

        max.x = (pos.x > max.x) ? pos.x : max.x
        max.y = (pos.y > max.y) ? pos.y : max.y
        min.x = (pos.x < min.x) ? pos.x : min.x
        min.y = (pos.y < min.y) ? pos.y : min.y
    }

    return (min, max)
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
    return float2(randFloat(min, max), randFloat(min, max))
}

/**
 Returns a random float3 between min and max
 */
func randFloat3(_ min: Float, _ max: Float) -> float3 {
    return float3(randFloat(min, max), randFloat(min, max), randFloat(min, max))
}

/**
 Returns a random float4 between min and max
 */
func randFloat4(_ min: Float, _ max: Float) -> float4 {
    return float4(randFloat(min, max), randFloat(min, max), randFloat(min, max), randFloat(min, max))
}

func hsv2rgb(_ h: Int, _ s: Float, _ v: Float, _ a: Float) -> float4 {
    // gray
    if s == 0.0 { return float4(v, v, v, a) }

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

    switch i % 6 {
    case 0: r = v; g = t; b = p
    case 1: r = q; g = v; b = p
    case 2: r = p; g = v; b = t
    case 3: r = p; g = q; b = v
    case 4: r = t; g = p; b = v
    case 5: r = v; g = p; b = q
    default: r = v; g = t; b = p
    }

    return float4(r, g, b, a)
}

/**
 Returns the RGBA ekvivalent of the HSV input
 */
func HSVtoRGBA(_ h: Int, _ s: Float, _ v: Float, _ a: Float) -> float4 {
    // gray
    if s == 0.0 { return float4(v, v, v, a) }

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

    out.z = max // v

    out.w = rgba.w

    delta = max - min
    if delta < 0.00001 {
        out.y = 0
        out.x = 0 // undefined, maybe nan?
        return out
    }
    if max > 0.0 { // NOTE: if Max is == 0, this divide would cause a crash
        out.y = (delta / max) // s
    } else {
        // if max is 0, then r = g = b = 0
        // s = 0, h is undefined
        out.y = 0.0
        out.x = Float(FP_NAN) // its now undefined
        return out
    }

    if rgba.x >= max { // > is bogus, just keeps compilor happy
        out.x = (rgba.y - rgba.z) / delta // between yellow & magenta
    } else if rgba.y >= max {
        out.x = 2.0 + (rgba.z - rgba.x) / delta // between cyan & yellow
    } else {
        out.x = 4.0 + (rgba.x - rgba.y) / delta // between magenta & cyan
    }
    out.x *= 60.0 // degrees
    if out.x < 0.0 { out.x += 360.0 }

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
        A.x += 1 // 360deg
        h = (A.x + T * (B.x - A.x)) // 360deg
    }
    if d <= 0.5 { // 180deg
        h = A.x + T * d
    }

    h = h > 360 ? 360 : h < 0 ? 0 : h

    // Interpolates the rest
    return float4(h, // H
                  A.y + T * (B.y - A.y), // S
                  A.z + T * (B.z - A.z), // V
                  A.w + T * (B.w - A.w) // A
    )
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

func fade(_ t: Float) -> Float { return t * t * t * (t * (t * 6 - 15) + 10) }
func lerp(_ t: Float, _ a: Float, _ b: Float) -> Float { return a + t * (b - a) }
func grad(_ hash: Int32, _ x: Float, _ y: Float, _ z: Float) -> Float {
    let h: Int32 = hash & 15
    let u: Float = h < 8 ? x : y
    let v: Float = h < 4 ? y : h == 12 || h == 14 ? x : z
    return ((h & 1) == 0 ? u : -u) + ((h & 2) == 0 ? v : -v)
}

//func noise(_ p: inout [Int32], _ x1: Float, _ y1: Float, _ z1: Float) -> Float {
//
//    let X: Int = Int(Int32(floorf(x1)) & 255)
//    let Y: Int = Int(Int32(floorf(y1)) & 255)
//    let Z: Int = Int(Int32(floorf(z1)) & 255)
//
//    let x = x1 - floorf(x1)
//    let y = y1 - floorf(y1)
//    let z = z1 - floorf(z1)
//
//    let u = fade(x)
//    let v = fade(y)
//    let w = fade(z)
//
//    let A: Int = Int(p[X] + Y)
//    let AA: Int = Int(p[A] + Z)
//    let AB: Int = Int(p[A + 1] + Z)
//
//    let B: Int = Int(p[X + 1] + Y)
//    let BA: Int = Int(p[B] + Z)
//    let BB: Int = Int(p[B + 1] + Z)
//
//    return lerp(w, lerp(v, lerp(u, grad(p[AA], x, y, z),
//                                grad(p[BA], x - 1, y, z)),
//                        lerp(u, grad(p[AB], x, y - 1, z),
//                             grad(p[BB], x - 1, y - 1, z))),
//                lerp(v, lerp(u, grad(p[AA + 1], x, y, z - 1),
//                             grad(p[BA + 1], x - 1, y, z - 1)),
//                     lerp(u, grad(p[AB + 1], x, y - 1, z - 1),
//                          grad(p[BB + 1], x - 1, y - 1, z - 1))));
//}
//void reseed()
//    {
//        for (std::int32_t i = 0; i < 256; ++i)
//        p[i] = i;
//        std::uint32_t seed = std::default_random_engine::default_seed;
//        std::shuffle(std::begin(p), std::begin(p) + 256, std::default_random_engine(seed));
//        for (size_t i = 0; i < 256; ++i)
//        p[256 + i] = p[i];
//}

