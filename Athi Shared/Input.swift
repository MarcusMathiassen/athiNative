//
//  Input.swift
//  Athi
//
//  Created by Marcus Mathiassen on 04/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

enum MouseOption: Int {
    case spawn = 0
    case drag = 1
    case color = 2
    case repel = 3
}

var gMouseOption = MouseOption.spawn
var mouseSize: Float = 20.0
var isMouseDown: Bool = false
var isMouseDragging: Bool = false
var gmouseAttachedToIDs: [Int] = []
