//
//  Math.swift
//  Athi
//
//  Created by Marcus Mathiassen on 03/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

import simd

// swiftlint:disable identifier_name

/**
 Returns projection matrix
 */
func makeProj(aspect: Float, fovy: Float, near: Float, far: Float) -> float4x4 {
    let yScale: Float = 1 / tan(fovy * 0.5)
    let xScale: Float = yScale / aspect
    let zRange: Float = far - near
    let zScale: Float = -(far + near) / zRange
    let wzScale: Float = -2 * far * near / zRange

    let P = float4(xScale, 0, 0, 0)
    let Q = float4(0, yScale, 0, 0)
    let R = float4(0, 0, zScale, -1)
    let S = float4(0, 0, wzScale, 0)

    return float4x4(P, Q, R, S)
}

/**
 Returns orthographic projection matrix
 */
func makeOrtho(left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) -> float4x4 {
    let ral = right + left
    let tab = top + bottom

    let sLength = 1 / (right - left)
    let sHeight = 1 / (top - bottom)
    let sDepth = 1 / (far - near)

    let P = float4(2.0 * sLength, 0, 0, 0)
    let Q = float4(0, 2.0 * sHeight, 0, 0)
    let R = float4(0, 0, sDepth, 0)
    let S = float4(-ral * sLength, -tab * sHeight, -near * sDepth, 1)

    return float4x4(P, Q, R, S)
}

/**
 Return the rotation matrix
 */
func makeRotate(angle: Float, x: Float, y: Float, z: Float) -> float4x4 {
    let c = cos(angle)
    let s = sin(angle)

    var X = float4()
    X.x = (x * x + (1 - x * x) * c)
    X.y = (x * y * (1 - c) - z * s)
    X.z = (x * z * (1 - c) + y * s)
    X.w = 0

    var Y = float4()
    Y.x = (x * y * (1 - c) + z * s)
    Y.y = (y * y + (1 - y * y) * c)
    Y.z = (y * z * (1 - c) - x * s)
    Y.w = 0

    var Z = float4()
    Z.x = (x * z * (1 - c) - y * s)
    Z.y = (y * z * (1 - c) + x * s)
    Z.z = (z * z + (1 - z * z) * c)
    Z.w = 0

    let W = float4(0, 0, 0, 1)

    return float4x4(X, Y, Z, W)
}

/**
 Return the scale matrix
 */
func makeScale(_ v: float3) -> float4x4 {
    let x = float4(v.x, 0, 0, 0)
    let y = float4(0, v.y, 0, 0)
    let z = float4(0, 0, v.z, 0)
    let w = float4(0, 0, 0, 1)

    return float4x4(x, y, z, w)
}

/**
 Return the translation matrix
 */
func makeTranslate(_ v: float3) -> float4x4 {
    let x = float4(1, 0, 0, 0)
    let y = float4(0, 1, 0, 0)
    let z = float4(0, 0, 1, 0)
    let w = float4(v.x, v.y, v.z, 1)

    return float4x4(x, y, z, w)
}

/**
 Return the translation matrix
 */
func makeTranslate(_ v: float2) -> float3x3 {
    let X = float3(1, 0, 0)
    let Y = float3(0, 1, 0)
    let Z = float3(v.x, v.y, 1)

    return float3x3(X, Y, Z)
}

/**
 Return the rotation matrix
 */
func makeRotate(theta: Float) -> float3x3 {
    let X = float3(cos(theta), sin(theta), 0)
    let Y = float3(-sin(theta), cos(theta), 0)
    let Z = float3(0, 0, 1)

    return float3x3(X, Y, Z)
}

/**
 Return the scale matrix
 */
func makeScale(_ v: float2) -> float3x3 {
    let X = float3(v.x, 0, 0)
    let Y = float3(0, v.y, 0)
    let Z = float3(0, 0, 1)

    return float3x3(X, Y, Z)
}

struct Transform {
    var pos     = float2(0)
    var rot     = Float(0)
    var scale   = float2(1)

    func getModel() -> float3x3 {
        let posMatrix = makeTranslate(pos)
        let rotMatrix = makeRotate(theta: rot)
        let scaleMatrix = makeScale(scale)

        return posMatrix * rotMatrix * scaleMatrix
    }
}

// struct Transform {
//     var pos = float3(0, 0, 0)
//     var rot = float3(0, 0, 0)
//     var scale = float3(1, 1, 1)

//     func getModel() -> float4x4 {
//         let posMatrix = makeTranslate(pos)
//         let rotXMatrix = makeRotate(angle: rot.x, x: 1, y: 0, z: 0)
//         let rotYMatrix = makeRotate(angle: rot.y, x: 0, y: 1, z: 0)
//         let rotZMatrix = makeRotate(angle: rot.z, x: 0, y: 0, z: 1)
//         let scaleMatrix = makeScale(scale)

//         let rotMatrix = rotZMatrix * rotYMatrix * rotXMatrix

//         return posMatrix * rotMatrix * scaleMatrix
//     }
// }
