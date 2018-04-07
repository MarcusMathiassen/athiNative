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
    
    var mtkView: MTKView?
    var timer: Timer?
    var renderer: Renderer!

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
        mousePos = float2(Float(event.locationInWindow.x), Float(event.locationInWindow.y))
        mousePos *= pixelScale
    }
    
    override func mouseDown(with event: NSEvent) {
        isMouseDown = true
    }
    
    override func rightMouseDown(with event: NSEvent) {
        renderer.particleSystem.addParticle(position: mousePos, color: colorOverTime(getTime()), radius: particleSize)
    }
    
    override func mouseUp(with event: NSEvent) {
        isMouseDown = false
    }

    @IBAction func particleUpdateSamples(_ sender: NSSliderCell) {
        renderer.particleSystem.samples = Int(sender.intValue)
    }
    @IBAction func particleCollisionButton(_ sender: NSButton) {
        renderer.particleSystem.enableCollisions = (sender.state.rawValue == 0) ? false : true
    }
    @IBAction func gravitySwitch(_ sender: NSButton) {
        renderer.particleSystem.enableGravity = (sender.state.rawValue == 0) ? false : true
    }
    @IBOutlet weak var particleColorWellOutlet: NSColorWell!
    @IBAction func particleColorWell(_ sender: NSColorWell) {
        
        let color = sender.color.usingColorSpace(colorSpace!)!
        
        renderer.particleSystem.particleColor = float4(Float(color.redComponent), Float(color.greenComponent), Float(color.blueComponent), Float(color.alphaComponent))
    }
    @IBAction func backgroundColorWell(_ sender: NSColorWell) {
        backgroundColor =  sender.color.usingColorSpace(colorSpace!)!
    }
    @IBAction func postProcessingSamplesSlier(_ sender: NSSlider) {
        renderer.postProcessingSamples = Int(sender.intValue)
    }
    @IBAction func postprocessingButton(_ sender: NSButton) {
        renderer.enablePostProcessing = (sender.state.rawValue == 0) ? false : true
    }
    @IBAction func useQuadtree(_ sender: NSButton) {
        renderer.particleSystem.useQuadtree = (sender.state.rawValue == 0) ? false : true
    }
    @IBAction func wireframeSwitch(_ sender: NSButton) {
        renderer.fillMode = (sender.state.rawValue == 0) ? .fill : .lines
    }
    @IBAction func multithreadedSwitch(_ sender: NSButton) {
        renderer.particleSystem.enableMultithreading = (sender.state.rawValue == 0) ? false : true
    }
    @IBAction func cycleColorSwitch(_ sender: NSButton) {
        particleColorCycle = (sender.state.rawValue == 0) ? false : true
    }
    @IBOutlet weak var framerateLabel: NSTextField!
    @IBOutlet weak var frametimeLabel: NSTextField!
    @IBOutlet weak var particleCountLabel: NSTextField!
    
    @IBAction func clearParticlesButton(_ sender: NSButton) {
        renderer.particleSystem.eraseParticles()
    }
    @IBAction func blurStrengthSlider(_ sender: NSSlider) {
        renderer.blurStrength = sender.floatValue

    }
    @IBAction func particleVerticesStepper(_ sender: NSStepper) {
       let val = Int(sender.intValue)
        renderer.particleSystem.setVerticesPerParticle(num: val == 0 ? 9 : val)
    }

    @IBAction func particleSizeSlider(_ sender: NSSlider) {
        particleSize = sender.floatValue
    }
    
    func startVariableUpdater() {
        // Configure a timer to fetch the data.
        self.timer = Timer(fire: Date(), interval: (1.0/60.0),
                           repeats: true, block: { (timer) in
                            
                            self.particleCountLabel?.stringValue = "Particles: " + String(self.renderer.particleSystem.particles.count)
                            
                            self.frametimeLabel?.stringValue = "Frametime: " + String(self.renderer.frametime)
                            
                                                        self.framerateLabel?.stringValue = "Framerate: " + String(self.renderer.framerate)
                            
                            
                            let pc = NSColor(
                                red: CGFloat(self.renderer.particleSystem.particleColor.x),
                                green: CGFloat(self.renderer.particleSystem.particleColor.y),
                                blue: CGFloat(self.renderer.particleSystem.particleColor.z),
                                alpha: CGFloat(self.renderer.particleSystem.particleColor.w)
                                )

                                
                            self.particleColorWellOutlet.color = pc
                            
        })
        
        // Add the timer to the current run loop.
        RunLoop.current.add(self.timer!, forMode: .defaultRunLoopMode)
    }
    

    override func viewDidLoad() {
        super.viewDidLoad()
        
        startVariableUpdater()
        
        
        colorSpace = NSScreen.screens[0].colorSpace!
        pixelScale = Float(NSScreen.screens[0].backingScaleFactor)
    
        screenWidth = Float(view.frame.width)
        screenHeight = Float(view.frame.height)
        
        framebufferWidth = Float(view.frame.width) * pixelScale
        framebufferHeight = Float(view.frame.height) * pixelScale

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
