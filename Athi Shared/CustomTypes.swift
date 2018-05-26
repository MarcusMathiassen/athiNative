//
//  CustomTypes.swift
//  Athi
//
//  Created by Marcus Mathiassen on 15/05/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

import simd.vector_types
import Accelerate.vImage

typealias Half = UInt16

func toHalf4(_ input: float4) -> half4 {
    var ink = input
    var value: [Half] = [0, 0, 0, 0]
    var bufferFloat32 = vImage_Buffer(data: &ink, height: 1, width: 4, rowBytes: 4)
    var bufferFloat16 = vImage_Buffer(data: &value, height: 1, width: 4, rowBytes: 2)
    
    if vImageConvert_PlanarFtoPlanar16F(&bufferFloat32, &bufferFloat16, 0) != kvImageNoError {
        print("Error converting float32 to float16")
    }
    
    var res = half4()
    res.x = value[0]
    res.y = value[1]
    res.z = value[2]
    res.w = value[3]
    
    return res
}

func toHalf(_ input: [Float]) -> [Half] {
    var ink = input
    var value = [Half](repeating: Half(), count: input.count)
    var bufferFloat32 = vImage_Buffer(data: &ink, height: 1, width: UInt(input.count), rowBytes: 4)
    var bufferFloat16 = vImage_Buffer(data: &value, height: 1, width: UInt(input.count), rowBytes: 2)
    
    if vImageConvert_PlanarFtoPlanar16F(&bufferFloat32, &bufferFloat16, 0) != kvImageNoError {
        print("Error converting float32 to float16")
    }
    return value
}

func toHalf(_ input: Float32) -> Half {
    var ink = input
    var value: Half = 0
    var bufferFloat32 = vImage_Buffer(data: &ink, height: 1, width: 1, rowBytes: 4)
    var bufferFloat16 = vImage_Buffer(data: &value, height: 1, width: 1, rowBytes: 2)
    
    if vImageConvert_PlanarFtoPlanar16F(&bufferFloat32, &bufferFloat16, 0) != kvImageNoError {
        print("Error converting float32 to float16")
    }
    return value
}

struct half4 {
    
    var x, y, z, w: Half
    
    init() {
        self.x = 0
        self.y = 0
        self.z = 0
        self.w = 0
    }
    init(_ v: Float) {
        let temp = toHalf4(float4(v))
        self.x = temp.x
        self.y = temp.y
        self.z = temp.z
        self.w = temp.w
    }
    init(_ x: Float, _ y: Float, _ z: Float, _ w: Float) {
        let temp = toHalf4(float4(x, y, z, w))
        self.x = temp.x
        self.y = temp.y
        self.z = temp.z
        self.w = temp.w
    }
    init(_ v: float4) {
        let temp = toHalf4(v)
        self.x = temp.x
        self.y = temp.y
        self.z = temp.z
        self.w = temp.w
    }
}
