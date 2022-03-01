//
//  ControlCenter.swift
//  Michael Wu
//
//  Created by Michael Wu on 9/11/2021
//

import Foundation
import ARKit
import os
import Network
import CoreMotion

class ControlCenter {
    public var vehicleState: VehicleState = VehicleState()
    public var transform: CustomTransform = CustomTransform()
    public var vel_x: Float = 0; // m/sec
    public var vel_y: Float = 0; // m/sec
    public var vel_z: Float = 0; // m/sec
    public var control: CustomControl = CustomControl()
    
    public var backCamImage: CustomImage!

    public var worldCamDepth: CustomDepthData!
    
    public var vc: ViewController!
    
    private var prevTransformUpdateTime: TimeInterval?;
    let motion = CMMotionManager()
    
    init(vc: ViewController) {
        self.vc = vc
        self.backCamImage = CustomImage(compressionQuality: 0.005, ratio: .no_cut)//AppInfo.imageRatio)
        self.worldCamDepth = CustomDepthData()
        if self.motion.isAccelerometerAvailable {
              self.motion.accelerometerUpdateInterval = 1.0 / 60.0  // 60 Hz
              self.motion.startAccelerometerUpdates()
        }
        if self.motion.isGyroAvailable {
            self.motion.gyroUpdateInterval = 1.0 / 60.0
            self.motion.startGyroUpdates()
        }
    }
    
    func start(shouldStartServer: Bool = true){
        if shouldStartServer {
            
        }
    }
    func stop(){

    }
    
    
    func restartUDP() {

    }
    public func updateBackCam(frame:ARFrame) {
        if self.backCamImage.updating == false {
            self.backCamImage.updateImage(cvPixelBuffer: frame.capturedImage)
            self.backCamImage.updateIntrinsics(intrinsics: frame.camera.intrinsics)
        }
    }
    public func updateBackCam(cvpixelbuffer:CVPixelBuffer, rotationDegree:Float=90) {
        if self.backCamImage.updating == false {
            self.backCamImage.updateImage(cvPixelBuffer: cvpixelbuffer)
        }
    }
    public func updateWorldCamDepth(frame: ARFrame) {
        if self.worldCamDepth.updating == false {
            self.worldCamDepth.update(frame: frame)
        }
    }

    
    public func updateTransform(pointOfView: SCNNode) {
        let node = pointOfView
        let time = TimeInterval(NSDate().timeIntervalSince1970)
        if prevTransformUpdateTime == nil {
            prevTransformUpdateTime = time
        } else {
            
            let time_diff = Float((time-prevTransformUpdateTime!))
            
            vel_x = (node.position.x-self.transform.position.x) / time_diff // m/s
            vel_y = (node.position.y-self.transform.position.y) / time_diff
            vel_z = (node.position.z-self.transform.position.z) / time_diff
            
            let recv_time = time - TimeInterval(Int(time / 1000) * 1000)
            
            self.transform.position = node.position
            
            // yaw, roll, pitch DO NOT CHANGE THIS!
            self.transform.eulerAngle = SCNVector3(node.eulerAngles.z, node.eulerAngles.y, node.eulerAngles.x)
            
            if let accData = self.motion.accelerometerData, let gyroData = self.motion.gyroData {
                let ax = Float(accData.acceleration.x)
                let ay = Float(accData.acceleration.y)
                let az = Float(accData.acceleration.z)
                let gx = Float(gyroData.rotationRate.x)
                let gy = Float(gyroData.rotationRate.y)
                let gz = Float(gyroData.rotationRate.z)
                self.vehicleState.update(x: transform.position.x,
                                         y: transform.position.y,
                                         z: transform.position.z,
                                         roll: transform.eulerAngle.z,
                                         pitch: transform.eulerAngle.y,
                                         yaw: transform.eulerAngle.x,
                                         vx: vel_x, //self.vehicleState.ax * time_diff,
                                         vy: vel_y, //self.vehicleState.ay * time_diff,
                                         vz: vel_z, //self.vehicleState.az * time_diff,
                                         ax: ax,
                                         ay: az,
                                         az: ay,
                                         gx: gx,
                                         gy: gz,
                                         gz: gy,
                                         recv_time: recv_time
                                         
                )
            }
            
           
//            print("vx: \(vel_x) | vy: \(vel_y) | vz: \(vel_z)")
            prevTransformUpdateTime = time
        }
    }
}
