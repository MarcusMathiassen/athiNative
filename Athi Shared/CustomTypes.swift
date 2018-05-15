//
//  CustomTypes.swift
//  Athi
//
//  Created by Marcus Mathiassen on 15/05/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

import simd.vector_types
import Accelerate.vImage

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

    var x: UInt16
    var y: UInt16
    var z: UInt16
    var w: UInt16

    init(_ x: Float32, _ y: Float32, _ z: Float32, _ w: Float32) {
        self.x = float32tofloat16(x)
        self.y = float32tofloat16(y)
        self.z = float32tofloat16(z)
        self.w = float32tofloat16(w)
    }

    init(_ v: float4) {
        self.x = float32tofloat16(v.x)
        self.y = float32tofloat16(v.y)
        self.z = float32tofloat16(v.z)
        self.w = float32tofloat16(v.w)
    }
}
