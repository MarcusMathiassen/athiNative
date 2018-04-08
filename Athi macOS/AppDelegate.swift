//
//  AppDelegate.swift
//  Athi macOS
//
//  Created by Marcus Mathiassen on 02/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        // Insert code here to initialize your application
    }

    func applicationWillTerminate(_: Notification) {
        // Insert code here to tear down your application
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        return true
    }
}
