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
    var timer: Timer?
    var renderer: Renderer!
    var mtkView: MTKView?

    // Allow view to receive keypress (remove the purr sound)
    override var acceptsFirstResponder: Bool {
        return true
    }

    override func mouseMoved(with event: NSEvent) {
        mousePos = float2(Float(event.locationInWindow.x), Float(event.locationInWindow.y))
        mousePos *= gPixelScale
        // print("Mouse position:", mousePos)
    }

    override func scrollWheel(with event: NSEvent) {
        mouseSize += Float(event.scrollingDeltaY)
        if mouseSize < 0 { mouseSize = 1.0 }
        print(mouseSize)
    }

    override func mouseDragged(with event: NSEvent) {
        mousePos = float2(Float(event.locationInWindow.x), Float(event.locationInWindow.y))
        mousePos *= gPixelScale

        isMouseDragging = true
    }

    override func mouseDown(with _: NSEvent) {
        isMouseDown = true
    }

    override func rightMouseDown(with _: NSEvent) {
        renderer.particleSystem.attractPoint = mousePos
    }

    override func mouseUp(with _: NSEvent) {
        isMouseDown = false
        isMouseDragging = false
    }

    @IBAction func particleUpdateSamples(_ sender: NSSliderCell) {
    }

    @IBAction func particleCollisionButton(_ sender: NSButton) {
        renderer.particleSystem.enableCollisions = (sender.state.rawValue == 0) ? false : true
    }

    @IBAction func gravitySwitch(_ sender: NSButton) {
        renderer.particleSystem.enableGravity = (sender.state.rawValue == 0) ? false : true
    }

    @IBOutlet weak var emitterCountLabel: NSTextField!
    @IBOutlet var mouseOptionButton: NSPopUpButton!
    @IBOutlet var particleColorWellOutlet: NSColorWell!
    @IBAction func particleColorWell(_ sender: NSColorWell) {
        let color = sender.color.usingColorSpace(colorSpace!)!

        renderer.particleSystem.particleColor = float4(
            Float(color.redComponent),
            Float(color.greenComponent),
            Float(color.blueComponent),
            Float(color.alphaComponent)
        )
    }

    @IBAction func backgroundColorWell(_ sender: NSColorWell) {
        backgroundColor = sender.color.usingColorSpace(colorSpace!)!
    }

    @IBAction func postProcessingSamplesSlier(_ sender: NSSlider) {
        gLifetime = Float(Int(sender.intValue))
    }

    @IBAction func borderCollisionButton(_ sender: NSButton) {
        renderer.particleSystem.enableBorderCollision = (sender.state.rawValue == 0) ? false : true

    }
    @IBAction func postprocessingButton(_ sender: NSButton) {
        renderer.particleSystem.enablePostProcessing = (sender.state.rawValue == 0) ? false : true
    }

    @IBAction func useQuadtree(_ sender: NSButton) {
        renderer.particleSystem.useQuadtree = (sender.state.rawValue == 0) ? false : true
    }

    @IBAction func wireframeSwitch(_ sender: NSButton) {
        renderer.fillMode = (sender.state.rawValue == 0) ? .fill : .lines
    }

    @IBAction func cycleColorSwitch(_ sender: NSButton) {
        gParticleColorCycle = (sender.state.rawValue == 0) ? false : true
    }

    @IBOutlet var framerateLabel: NSTextField!
    @IBOutlet var particleCountLabel: NSTextField!

    @IBAction func treeOptimalSize(_ sender: NSButton) {
        gDrawDebug = (sender.state.rawValue == 0) ? false : true
    }

    @IBAction func clearParticlesButton(_: NSButton) {
        renderer.particleSystem.eraseParticles()
    }

    @IBAction func pauseButton(_ sender: NSButton) {
        let buttonState = (sender.state.rawValue == 0) ? false : true
        renderer.particleSystem.isPaused = buttonState
        if buttonState {
            sender.title = "Resume"
        } else {
            sender.title = "Pause"
        }
    }
    @IBAction func blurStrengthSlider(_ sender: NSSlider) {
        renderer.particleSystem.blurStrength = sender.floatValue
    }

    @IBAction func particleVerticesStepper(_ sender: NSStepper) {
        let val = Int(sender.intValue)
//        renderer.particleSystem.setVerticesPerParticle(num: val)
    }

    @IBAction func particleSizeSlider(_ sender: NSSlider) {
        gParticleSize = sender.floatValue
    }

    func startVariableUpdater() {
        // Configure a timer to fetch the data.
        timer = Timer(fire: Date(), interval: (1.0 / 60.0),
                      repeats: true, block: { _ in

                          self.particleCountLabel?.stringValue =
                            "Particles: " + String(self.renderer.particleSystem.particleCount)

                          self.framerateLabel?.stringValue = "Framerate: " + String(self.renderer.framerate)

                        self.emitterCountLabel?.stringValue = "Emitters: "
 + String(self.renderer.particleSystem.emitters.count)
                        
                          let particleColor = NSColor(
                              red: CGFloat(self.renderer.particleSystem.particleColor.x),
                              green: CGFloat(self.renderer.particleSystem.particleColor.y),
                              blue: CGFloat(self.renderer.particleSystem.particleColor.z),
                              alpha: CGFloat(self.renderer.particleSystem.particleColor.w)
                          )

                          self.particleColorWellOutlet.color = particleColor

                          let mouseVal = self.mouseOptionButton.indexOfSelectedItem
                          switch mouseVal {
                          case 0: gMouseOption = MouseOption.spawn
                          case 1: gMouseOption = MouseOption.color
                          case 2: gMouseOption = MouseOption.drag
                          case 3: gMouseOption = MouseOption.repel
                          default: break
                          }

                        switch self.computeDeviceOptionButton.indexOfSelectedItem {
                        case 0: gComputeDeviceOption = .gpu
                        case 1: gComputeDeviceOption = .cpu
                        default: break
                        }

                        switch self.treeOptionButton.indexOfSelectedItem {
                        case 0: gTreeOption = .quadtree
                        case 1: gTreeOption = .noTree
                        default: break
                        }

        })

        // Add the timer to the current run loop.
        RunLoop.current.add(timer!, forMode: .defaultRunLoopMode)
    }

    @IBOutlet weak var treeOptionButton: NSPopUpButton!
    @IBOutlet weak var computeDeviceOptionButton: NSPopUpButton!

    @IBAction func showMenuView(_ sender: NSButton) {
        let showMenu = (sender.intValue == 0) ? false : true
        if showMenu {
            menuView.animator().isHidden = false
        } else { menuView.animator().isHidden = true }
    }

    @IBOutlet weak var menuView: NSView!

    override func viewDidLoad() {
        super.viewDidLoad()

        startVariableUpdater()

        menuView.wantsLayer = true
        menuView.layer?.cornerRadius = 10.0

        colorSpace = NSScreen.screens[0].colorSpace!
        gPixelScale = Float(NSScreen.screens[0].backingScaleFactor)

        screenWidth = Float(view.frame.width)
        screenHeight = Float(view.frame.height)

        framebufferWidth = Float(view.frame.width) * gPixelScale
        framebufferHeight = Float(view.frame.height) * gPixelScale

        mouseOptionButton.addItem(withTitle: "Repel")

        guard let mtkView = self.view as? MTKView else {
            print("View attached to ViewController is not an MTKView")
            return
        }

        // Select the device to render with.  We choose the default device
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported on this device")
            return
        }

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
