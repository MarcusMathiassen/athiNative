//
//  Scene.swift
//  Athi
//
//  Created by Marcus Mathiassen on 04/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

import MetalKit
import simd // float4x4

class Scene {
    var entities: [Entity] = []
    var device: MTLDevice?

    init(device: MTLDevice?) {
        self.device = device
    }

    func update() {
        for entity in entities {
            entity.update()
        }
    }

    func render(renderEncoder: MTLRenderCommandEncoder?, vp: float4x4) {
        for entity in entities {
            entity.draw(renderEncoder: renderEncoder, vp: vp)
        }
//        print("Entites:", entities.count)
    }
}
