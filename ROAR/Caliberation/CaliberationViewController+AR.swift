//
//  CaliberationViewController+AR.swift
//  HardwarePID-ROAR
//
//  Created by 周翔宇 on 4/18/22.
//

//
//  ViewController+AR.swift
//  ROAR
//
//  Created by Michael Wu on 9/11/21.
//

import Foundation
import ARKit
extension CaliberationViewController:  ARSCNViewDelegate, ARSessionDelegate, ARSessionObserver{
    func startARSession(worldMap: ARWorldMap?, worldOriginTransform: SCNMatrix4? = nil ) {
        let referenceImages = ARReferenceImage.referenceImages(inGroupNamed: "AR Resources", bundle: nil)!
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = .horizontal
        configuration.isLightEstimationEnabled = false
        configuration.worldAlignment = .gravity
        configuration.wantsHDREnvironmentTextures = false
        configuration.detectionImages = referenceImages
        configuration.maximumNumberOfTrackedImages = 1
//        print(ARWorldTrackingConfiguration.supportedVideoFormats)
        if let format = ARWorldTrackingConfiguration.supportedVideoFormats.last  {
            configuration.videoFormat = format
        }
        if worldMap != nil {
            self.logger.info("Start AR Session from previous recorded world")
            // load the map
            configuration.initialWorldMap = worldMap
        } else {
            self.logger.info("Start AR Session from scratch")
        }
        
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth){
            configuration.frameSemantics.insert(.sceneDepth)
        }
        self.cali_AR.delegate = self
        self.cali_AR.session.delegate = self
        self.cali_AR.autoenablesDefaultLighting = true;
        
        self.cali_AR.showsStatistics = true
        self.cali_AR.debugOptions = [.showWorldOrigin, .showCameras, .showFeaturePoints]
        
        // Run the view's session
        self.cali_AR.session.run(configuration, options: [.resetTracking, .removeExistingAnchors, .resetSceneReconstruction])
        self.logger.info("AR Session Started")
    }
    
    func restartArSession() {
        self.cali_AR.session.pause()
        self.startARSession(worldMap: nil)
    }
    
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        switch camera.trackingState {
            case ARCamera.TrackingState.normal:
//                self.systemStatusLabel.textColor = .green
//                self.systemStatusLabel.text = "Tracking is normal"
                AppInfo.sessionData.isTracking = true
            case ARCamera.TrackingState.limited(.relocalizing):
//                self.systemStatusLabel.textColor = .red
//                self.systemStatusLabel.text = "Attempting to relocalize"
                AppInfo.sessionData.isTracking = false
            case ARCamera.TrackingState.limited(.excessiveMotion):
//                self.systemStatusLabel.textColor = .red
//                self.systemStatusLabel.text = "Excessive motion detected."
                AppInfo.sessionData.isTracking = false
            case ARCamera.TrackingState.limited(.initializing):
//                self.systemStatusLabel.textColor = .red
//                self.systemStatusLabel.text = "Tracking service is initializing"
                AppInfo.sessionData.isTracking = false
            case ARCamera.TrackingState.limited(.insufficientFeatures):
//                self.systemStatusLabel.textColor = .red
//                self.systemStatusLabel.text = "Not enough feature points"
                AppInfo.sessionData.isTracking = false
            default:
//                self.systemStatusLabel.textColor = .red
//                self.systemStatusLabel.text = "Not Available"
                AppInfo.sessionData.isTracking = false
        }
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        self.updateBackCam(frame: frame)
        self.updateTransform(pointOfView: self.cali_AR.pointOfView!)
        if frame.sceneDepth != nil {
            self.updateWorldCamDepth(frame:frame)
        }
    }
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        if AppInfo.sessionData.shouldCaliberate == true || AppInfo.sessionData.isCaliberated == false{
            for anchor in anchors {
                guard let imageAnchor = anchor as? ARImageAnchor else { continue }
                if imageAnchor.name == "BerkeleyLogo" {
                    session.setWorldOrigin(relativeTransform: imageAnchor.transform)
                    AppInfo.sessionData.isCaliberated = true
                    AppInfo.sessionData.shouldCaliberate = false
                    print(1)
                }

            }
        }
        for anchor in anchors {
            guard let imageAnchor = anchor as? ARImageAnchor else { continue }
            if imageAnchor.name == "campanille" {
                guard let camera = session.currentFrame?.camera else { return }
                let cameraPosition = camera.transform.columns.3
                self.follow_x = imageAnchor.transform.columns.3.x - cameraPosition.x
                self.follow_y = imageAnchor.transform.columns.3.y - cameraPosition.y
                self.follow_z = imageAnchor.transform.columns.3.z - cameraPosition.z
                print("x:\(self.follow_x * 100)") //左右，往左变大，往右变小
                print("y:\(self.follow_y * 100)") // 上下，往上变小，往下变大
                print("z:\(self.follow_z * 100)") // 前后， 往后变小，往前变大
                print("")
        }
    }
}

