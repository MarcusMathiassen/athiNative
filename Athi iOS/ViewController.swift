//
//  ViewController.swift
//  Athi
//
//  Created by Marcus Mathiassen on 02/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

import CoreMotion // gyro
import MetalKit
import UIKit

// Our IOS specific view controller
class IOSViewController: UIViewController {
    var timer: Timer?
    var motion = CMMotionManager()

    var renderer: Renderer!
    var mtkView: MTKView!

    @IBAction func enablePostProcessingSwitch(_ sender: UISwitch) {
        renderer.particleSystem.enablePostProcessing = sender.isOn
    }

    @IBAction func enableParticleCollision(_ sender: UISwitch) {
        renderer.particleSystem.enableCollisions = sender.isOn
    }

    @IBAction func useQuadtree(_ sender: UISwitch) {
        renderer.particleSystem.useQuadtree = sender.isOn
    }

    @IBAction func enableMultithreadingSwitch(_ sender: UISwitch) {
        renderer.particleSystem.enableMultithreading = sender.isOn
    }

    @IBAction func clearAllButton(_: UIButton) {
        renderer.particleSystem.eraseParticles()
    }

    @IBAction func blurStrengthSlider(_ sender: UISlider) {
        renderer.particleSystem.blurStrength = sender.value
    }
    @IBAction func particleSizeSlider(_ sender: UISlider) {
        particleSize = sender.value
    }

    @IBOutlet var particleCountLabel: UILabel?
    override func touchesMoved(_ touches: Set<UITouch>, with _: UIEvent?) {
        particleCountLabel?.text = "Particles: " + String(renderer.particleSystem.particleCount)

        for touch in touches {
            var point: float2 = float2(Float(touch.location(in: view).x), Float(touch.location(in: view).y))
            //            print(point)
            point *= 2
            point.y -= screenHeight
            point.y *= -1
            renderer.particleSystem.addParticleWith(position: point, color: renderer.particleSystem.particleColor, radius: particleSize)
            renderer.particleSystem.addParticleWith(position: point, color: renderer.particleSystem.particleColor, radius: particleSize)
            renderer.particleSystem.addParticleWith(position: point, color: renderer.particleSystem.particleColor, radius: particleSize)
            renderer.particleSystem.addParticleWith(position: point, color: renderer.particleSystem.particleColor, radius: particleSize)
            renderer.particleSystem.addParticleWith(position: point, color: renderer.particleSystem.particleColor, radius: particleSize)
            renderer.particleSystem.addParticleWith(position: point, color: renderer.particleSystem.particleColor, radius: particleSize)
            renderer.particleSystem.addParticleWith(position: point, color: renderer.particleSystem.particleColor, radius: particleSize)
            renderer.particleSystem.addParticleWith(position: point, color: renderer.particleSystem.particleColor, radius: particleSize)
            renderer.particleSystem.addParticleWith(position: point, color: renderer.particleSystem.particleColor, radius: particleSize)
            renderer.particleSystem.addParticleWith(position: point, color: renderer.particleSystem.particleColor, radius: particleSize)

            
            renderer.particleSystem.addParticleWith(position: point, color: renderer.particleSystem.particleColor, radius: particleSize)
            renderer.particleSystem.addParticleWith(position: point, color: renderer.particleSystem.particleColor, radius: particleSize)
            renderer.particleSystem.addParticleWith(position: point, color: renderer.particleSystem.particleColor, radius: particleSize)
            renderer.particleSystem.addParticleWith(position: point, color: renderer.particleSystem.particleColor, radius: particleSize)
            renderer.particleSystem.addParticleWith(position: point, color: renderer.particleSystem.particleColor, radius: particleSize)
            renderer.particleSystem.addParticleWith(position: point, color: renderer.particleSystem.particleColor, radius: particleSize)
            renderer.particleSystem.addParticleWith(position: point, color: renderer.particleSystem.particleColor, radius: particleSize)
            renderer.particleSystem.addParticleWith(position: point, color: renderer.particleSystem.particleColor, radius: particleSize)
            renderer.particleSystem.addParticleWith(position: point, color: renderer.particleSystem.particleColor, radius: particleSize)
            renderer.particleSystem.addParticleWith(position: point, color: renderer.particleSystem.particleColor, radius: particleSize)

        }
    }

    override func touchesBegan(_: Set<UITouch>, with _: UIEvent?) {
    }

    func startAccelerometers() {
        // Make sure the accelerometer hardware is available.
        if motion.isAccelerometerAvailable {
            motion.accelerometerUpdateInterval = 1.0 / 60.0 // 60 Hz
            motion.startAccelerometerUpdates()

            // Configure a timer to fetch the data.
            timer = Timer(fire: Date(), interval: (1.0 / 60.0),
                          repeats: true, block: { _ in
                              // Get the accelerometer data.
                              if let data = self.motion.accelerometerData {
                                  let x = data.acceleration.x
                                  let y = data.acceleration.y
                                  let z = data.acceleration.z

                                  // Use the accelerometer data in your app.
                                  accelerometer = float3(Float(x), Float(y), Float(z))
                              }
            })

            // Add the timer to the current run loop.
            RunLoop.current.add(timer!, forMode: .defaultRunLoopMode)
        }
    }

    @IBAction func computeDeviceSegmentedControl(_ sender: UISegmentedControl) {
        gComputeDeviceOption = (sender.selectedSegmentIndex == 0) ? .GPU : .CPU
    }
    func startGyros() {
        if motion.isGyroAvailable {
            motion.gyroUpdateInterval = 1.0 / 60.0
            motion.startGyroUpdates()

            // Configure a timer to fetch the accelerometer data.
            timer = Timer(fire: Date(), interval: (1.0 / 60.0),
                          repeats: true, block: { _ in
                              // Get the gyro data.
                              if let data = self.motion.gyroData {
                                  let x = data.rotationRate.x
                                  let y = data.rotationRate.y
                                  let z = data.rotationRate.z

                                  // Use the gyroscope data in your app.
                                  gyroRotation = float3(Float(x), Float(y), Float(z))
                              }
   
            })

            // Add the timer to the current run loop.
            RunLoop.current.add(timer!, forMode: .defaultRunLoopMode)
        }
    }

    func stopGyros() {
        if timer != nil {
            timer?.invalidate()
            timer = nil

            motion.stopGyroUpdates()
        }
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
