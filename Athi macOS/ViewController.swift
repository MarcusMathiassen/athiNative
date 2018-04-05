//
//  ViewController.swift
//  Athi
//
//  Created by Marcus Mathiassen on 02/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

import Cocoa
import MetalKit

// Our macOS specific view controller
class MACOSViewController: NSViewController {
    
    var renderer: Renderer!
    var mtkView: MTKView!

    // Allow view to receive keypress (remove the purr sound)
    override var acceptsFirstResponder : Bool {
        return true
    }
    
    override func mouseMoved(with event: NSEvent) {
        mousePos = float2(Float(event.locationInWindow.x), Float(event.locationInWindow.y))
        mousePos *= pixelScale
        //print("Mouse position:", mousePos)
    }
    
    override func mouseDragged(with event: NSEvent) {
        particleCountLabel?.stringValue = "Particles: " + String(renderer.particleSystem.particles.count)
        
        mousePos = float2(Float(event.locationInWindow.x), Float(event.locationInWindow.y))
        mousePos *= pixelScale
    }
    
    override func mouseDown(with event: NSEvent) {
        isMouseDown = true
        
        particleCountLabel?.stringValue = "Particles: " + String(renderer.particleSystem.particles.count)

    }
    
    override func rightMouseDown(with event: NSEvent) {
        renderer.particleSystem.addParticle(position: mousePos, color: colorOverTime(getTime()), radius: particleSize)
        particleCountLabel?.stringValue = "Particles: " + String(renderer.particleSystem.particles.count)
    }
    
    override func mouseUp(with event: NSEvent) {
        isMouseDown = false
    }

    @IBAction func particleCollisionButton(_ sender: NSButton) {
        renderer.particleSystem.enableCollisions = (sender.state.rawValue == 0) ? false : true
    }
    @IBAction func useQuadtree(_ sender: NSButton) {
        renderer.particleSystem.useQuadtree = (sender.state.rawValue == 0) ? false : true
    }
    @IBOutlet weak var particleCountLabel: NSTextField!
    
    @IBAction func clearParticlesButton(_ sender: NSButton) {
        renderer.particleSystem.eraseParticles()
    }
    @IBAction func particleSizeSlider(_ sender: NSSlider) {
        particleSize = sender.floatValue
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        guard let mtkView = self.view as? MTKView else {
            print("View attached to ViewController is not an MTKView")
            return
        }
        
        // Select the device to render with.  We choose the default device
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported on this device")
            return
        }
        
        print(defaultDevice.name)
        mtkView.device = defaultDevice
        
        guard let newRenderer = Renderer(view: mtkView) else {
            print("Renderer cannot be initialized")
            return
        }
        
        renderer = newRenderer
        
        renderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)
        
        mtkView.delegate = renderer
    }
}
