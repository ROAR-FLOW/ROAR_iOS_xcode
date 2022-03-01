//
//  ViewController+UDP.swift
//  ROAR
//
//  Created by Michael Wu on 11/4/21.
//

import Foundation
import CocoaAsyncSocket
import UIKit
import ARKit

extension ViewController: GCDAsyncUdpSocketDelegate {
    
    func setupSocket() {
        self.vehicleStateSocket = GCDAsyncUdpSocket(delegate: self, delegateQueue: DispatchQueue.global(qos: .background))
        self.worldCamSocket = GCDAsyncUdpSocket(delegate: self, delegateQueue: DispatchQueue.global(qos: .background))
        self.depthCamSocket = GCDAsyncUdpSocket(delegate: self, delegateQueue: DispatchQueue.global(qos: .background))
        self.controlSocket = GCDAsyncUdpSocket(delegate: self, delegateQueue: DispatchQueue.global(qos: .background))
        do {
            try self.worldCamSocket.bind(toPort: 8001)
            try self.depthCamSocket.bind(toPort: 8002)
            try self.vehicleStateSocket.bind(toPort: 8003)
            try self.controlSocket.bind(toPort: 8004)
            _ = try self.worldCamSocket.beginReceiving()
            _ = try self.depthCamSocket.beginReceiving()
            _ = try self.vehicleStateSocket.beginReceiving()
            _ = try self.controlSocket.beginReceiving()
        } catch let error {
            print(error)
        }
    }
    
    func udpSocket(_ sock: GCDAsyncUdpSocket, didConnectToAddress address: Data) {
        print("connected")
    }
    func udpSocket(_ sock: GCDAsyncUdpSocket, didReceive data: Data, fromAddress address: Data, withFilterContext filterContext: Any?) {
        if AppInfo.sessionData.isCaliberated && AppInfo.sessionData.shouldCaliberate == false {
            switch sock {
                case self.vehicleStateSocket:
                    self.chunkAndSendData(data: self.controlCenter.vehicleState.toData(), sock: sock, address: address)
                case self.worldCamSocket:
                    self.sendImage(customImage: self.controlCenter.backCamImage, sock: sock, address: address)
                case self.depthCamSocket:

                    self.sendDepth(customDepth: self.controlCenter.worldCamDepth, sock: sock, address: address)
                case self.controlSocket:

                    if let string = String(data: data, encoding: .utf8) {
                        let splitted = string.components(separatedBy: ",")
                        let throttle = Float(splitted[0])
                        let steering = Float(splitted[1])
                        
                        // Jerry
                        let kp = Float(splitted[2])
                        let ki = Float(splitted[3])
                        let kd = Float(splitted[4])
                        
                        if throttle != nil && steering != nil {
                            self.controlCenter.control.throttle = throttle!
                            self.controlCenter.control.steering = steering!
                        }
                        
                        // Jerry
                        if kp != nil && ki != nil && kd != nil {
                            self.controlCenter.control.kp = kp!
                            self.controlCenter.control.ki = ki!
                            self.controlCenter.control.kd = kd!
                        }
                    }
                default:
                    print("data received on unknown socket: \(String(describing: String(data: data, encoding: .utf8)))")
            }
        }
        
    }
    func udpSocketDidClose(_ sock: GCDAsyncUdpSocket, withError error: Error?) {
        print("socket is closed")
    }
    
    
    func sendDepth(customDepth: CustomDepthData, sock: GCDAsyncUdpSocket, address: Data) {
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            let current_frame = self.controlCenter.vc.arSceneView.session.currentFrame!
            let sceneDepth = current_frame.sceneDepth!
            let result = depthCVPixelToData(from: sceneDepth.depthMap)
            var intrinsics = self.updateIntrinsics(rgb_x: Float(current_frame.camera.imageResolution.height),
                                                   rgb_y: Float(current_frame.camera.imageResolution.width),
                                                   rgb_fx: current_frame.camera.intrinsics[0][0],
                                                   rgb_fy: current_frame.camera.intrinsics[1][1],
                                                   rgb_cx: current_frame.camera.intrinsics[2][0],
                                                   rgb_cy: current_frame.camera.intrinsics[2][1],
                                                   width: result.width,
                                                   height: result.height)
            var data = Data()
            withUnsafePointer(to: &intrinsics.fxD) { data.append(UnsafeBufferPointer(start: $0, count: 1)) } // ok
            withUnsafePointer(to: &intrinsics.fyD) { data.append(UnsafeBufferPointer(start: $0, count: 1)) } // ok
            withUnsafePointer(to: &intrinsics.cxD) { data.append(UnsafeBufferPointer(start: $0, count: 1)) } // ok
            withUnsafePointer(to: &intrinsics.cyD) { data.append(UnsafeBufferPointer(start: $0, count: 1)) } // ok
            data.append(result.data)
            chunkAndSendData(data: data, sock: sock, address: address)
        }
    }
    
    func updateIntrinsics(rgb_x:Float, rgb_y:Float, rgb_fx: Float, rgb_fy: Float, rgb_cx:Float, rgb_cy: Float, width:Int, height:Int) -> (fxD: Float, fyD: Float, cxD: Float, cyD: Float){
        let y = Float(width)
        let x = Float(height)
        let fxD = x / rgb_x * rgb_fx
        let fyD = y / rgb_y * rgb_fy
        let cxD = x / rgb_x * rgb_cx
        let cyD = y / rgb_y * rgb_cy
        return (fxD, fyD, cxD, cyD)
    }
    
    func depthCVPixelToData(from pixelBuffer: CVPixelBuffer) -> (data:Data, width:Int, height:Int)  {
        
        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        var data = Data()
        let yBaseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)
        let yBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let yLength = yBytesPerRow *  height
        data.append(Data(bytes: yBaseAddress!, count: yLength))
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        
        return (data, width, height)
    }
    
    func sendImage(customImage: CustomImage, sock: GCDAsyncUdpSocket, address: Data) {
        let current_frame = self.controlCenter.vc.arSceneView.session.currentFrame!
        var data = Data()
        var fx = current_frame.camera.intrinsics[0][0]
        var fy = current_frame.camera.intrinsics[1][1]
        var cx = current_frame.camera.intrinsics[2][0]
        var cy = current_frame.camera.intrinsics[2][1]
       withUnsafePointer(to: &fx) { data.append(UnsafeBufferPointer(start: $0, count: 1)) }
       withUnsafePointer(to: &fy) { data.append(UnsafeBufferPointer(start: $0, count: 1)) }
       withUnsafePointer(to: &cx) { data.append(UnsafeBufferPointer(start: $0, count: 1)) }
       withUnsafePointer(to: &cy) { data.append(UnsafeBufferPointer(start: $0, count: 1)) }
        
        let image_data = UIImage(pixelBuffer: current_frame.capturedImage)?.jpegData(compressionQuality: 0.1)
        data.append(image_data!)
        self.chunkAndSendData(data: data, sock: sock, address: address)

    }
    
    
    func chunkAndSendData(data: Data, sock: GCDAsyncUdpSocket, address: Data) {
        data.withUnsafeBytes{(u8Ptr: UnsafePointer<UInt8>) in
            let mutRawPointer = UnsafeMutableRawPointer(mutating: u8Ptr)
            let uploadChunkSize = 9200
            let totalSize = data.count
            var offset = 0
            var counter = 0 // Int(Float(totalSize / uploadChunkSize).rounded(.up)) + 1
            let total = Int(Float(totalSize / uploadChunkSize).rounded(.up))
            while offset < totalSize {
                var data_to_send:Data = String(counter).leftPadding(toLength: 3, withPad: "0")
                    .data(using:.ascii)!
                
                data_to_send.append(String(total).leftPadding(toLength: 3, withPad: "0").data(using: .ascii)!)
                data_to_send.append(String(0).leftPadding(toLength: 3, withPad: "0").data(using: .ascii)!)
                
                let chunkSize = offset + uploadChunkSize > totalSize ? totalSize - offset : uploadChunkSize
                let chunk = Data(bytesNoCopy: mutRawPointer+offset, count: chunkSize, deallocator: Data.Deallocator.none)
                data_to_send.append(chunk)
                sock.send(data_to_send, toAddress: address, withTimeout: 0.1, tag: -1)
                offset += chunkSize
                counter += 1
            }
        }
    }
}
