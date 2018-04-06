//
//  ViewController.swift
//  Athi
//
//  Created by Marcus Mathiassen on 02/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

import UIKit
import MetalKit
import CoreMotion // gyro

// Our IOS specific view controller
class IOSViewController: UIViewController {
    
    var timer: Timer?
    var motion = CMMotionManager()
    
    var renderer: Renderer!
    var mtkView: MTKView!
    
    @IBAction func enablePostProcessingSwitch(_ sender: UISwitch) {
        renderer.enablePostProcessing = sender.isOn
    }
    @IBAction func enableParticleCollision(_ sender: UISwitch) {
        renderer.particleSystem.enableCollisions = sender.isOn
    }
    @IBAction func useQuadtree(_ sender: UISwitch) {
        renderer.particleSystem.useQuadtree = sender.isOn
    }
    @IBAction func enableMultithreadingSwitch(_ sender: UISwitch) {
        useMultihreading = sender.isOn

    }
    
    @IBAction func clearAllButton(_ sender: UIButton) {
        renderer.particleSystem.eraseParticles()
    }
    @IBAction func particleSizeSlider(_ sender: UISlider) {
        particleSize = sender.value
    }
    @IBOutlet weak var particleCountLabel: UILabel?
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {

       particleCountLabel?.text = "Particles: " + String(renderer.particleSystem.particles.count)

        for touch in touches {
            
            var point: float2 = float2( Float(touch.location(in: self.view).x), Float(touch.location(in: self.view).y))
            //            print(point)
            point *= 2
            point.y -= screenHeight
            point.y *= -1
            renderer.particleSystem.addParticle(position: point, color: colorOverTime(getTime()), radius: particleSize)
            renderer.particleSystem.addParticle(position: point, color: colorOverTime(getTime()), radius: particleSize)
            renderer.particleSystem.addParticle(position: point, color: colorOverTime(getTime()), radius: particleSize)
            renderer.particleSystem.addParticle(position: point, color: colorOverTime(getTime()), radius: particleSize)
            renderer.particleSystem.addParticle(position: point, color: colorOverTime(getTime()), radius: particleSize)
            renderer.particleSystem.addParticle(position: point, color: colorOverTime(getTime()), radius: particleSize)
            renderer.particleSystem.addParticle(position: point, color: colorOverTime(getTime()), radius: particleSize)
        }
    }
    
    
    func startAccelerometers() {
        // Make sure the accelerometer hardware is available.
        if self.motion.isAccelerometerAvailable {
            self.motion.accelerometerUpdateInterval = 1.0 / 60.0  // 60 Hz
            self.motion.startAccelerometerUpdates()
            
            // Configure a timer to fetch the data.
            self.timer = Timer(fire: Date(), interval: (1.0/60.0),
                               repeats: true, block: { (timer) in
                                // Get the accelerometer data.
                                if let data = self.motion.accelerometerData {
                                    let x = data.acceleration.x
                                    let y = data.acceleration.y
                                    let z = data.acceleration.z
                                    
                                    // Use the accelerometer data in your app.
                                    accelerometer = float3(Float(x),Float(y),Float(z))
                                }
            })
            
            // Add the timer to the current run loop.
            RunLoop.current.add(self.timer!, forMode: .defaultRunLoopMode)
        }
    }
    
    func startGyros() {
        if motion.isGyroAvailable {
            self.motion.gyroUpdateInterval = 1.0 / 60.0
            self.motion.startGyroUpdates()
            
            // Configure a timer to fetch the accelerometer data.
            self.timer = Timer(fire: Date(), interval: (1.0/60.0),
                               repeats: true, block: { (timer) in
                                // Get the gyro data.
                                if let data = self.motion.gyroData {
                                    let x = data.rotationRate.x
                                    let y = data.rotationRate.y
                                    let z = data.rotationRate.z
                                    
                                    // Use the gyroscope data in your app.
                                    gyroRotation = float3(Float(x),Float(y),Float(z))
                                }
            })
            
            // Add the timer to the current run loop.
            RunLoop.current.add(self.timer!, forMode: .defaultRunLoopMode)
        }
    }
    
    func stopGyros() {
        if self.timer != nil {
            self.timer?.invalidate()
            self.timer = nil
            
            self.motion.stopGyroUpdates()
        }
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        print("TOUCHED")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        pixelScale = 2
        
        screenWidth = Float(view.frame.width)
        screenHeight = Float(view.frame.height)
        
        framebufferWidth = Float(view.frame.width) * pixelScale
        framebufferHeight = Float(view.frame.height) * pixelScale

        
        startAccelerometers()
        startGyros()
        view.isMultipleTouchEnabled = true
        
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
