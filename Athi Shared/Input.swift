//
//  Input.swift
//  Athi
//
//  Created by Marcus Mathiassen on 04/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

enum MouseOption: Int {
    case Spawn = 0
    case Drag = 1
    case Color = 2
    case Repel = 3
}

var gMouseOption = MouseOption.Spawn
var mouseSize: Float = 20.0
var isMouseDown: Bool = false
var isMouseDragging: Bool = false
var gmouseAttachedToIDs: [Int] = []

enum KEY_CODES: Int {
    case Key_W = 13
    case Key_S = 1
    case Key_A = 0
    case Key_D = 2
    case Key_1 = 18
    case Key_2 = 19
    case Key_3 = 20
    case Key_4 = 21

    case Key_Arrow_Up = 126
    case Key_Arrow_Down = 125
    case Key_Arrow_Left = 123
    case Key_Arrow_Right = 124
}

private var KEY_COUNT = 256

private var keyList = [Bool].init(repeating: false, count: KEY_COUNT)

func setKeyPressed(key: UInt16, isOn: Bool) {
    keyList[Int(key)] = isOn
}

func isKeyPressed(key: KEY_CODES) -> Bool {
    return keyList[Int(key.rawValue)] == true
}
