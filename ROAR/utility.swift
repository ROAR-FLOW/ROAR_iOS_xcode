//
//  utility.swift
//  ROAR
//
//  Created by Michael Wu on 9/11/21.
//

import Foundation
import UIKit
import ARKit
import UIKit
import VideoToolbox

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}
extension String {
    func leftPadding(toLength: Int, withPad character: Character) -> String {
        let newLength = self.count
        if newLength < toLength {
            return String(repeatElement(character, count: toLength - newLength)) + self
        } else {
            return self.substring(from: index(self.startIndex, offsetBy: newLength - toLength))
        }
    }
}

func findIPAddr() -> String {
    var address: String?
    var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
    if getifaddrs(&ifaddr) == 0 {
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            
            guard let interface = ptr?.pointee else { return "" }
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) {
                
                // wifi = ["en0"]
                // wired = ["en2", "en3", "en4"]
                // cellular = ["pdp_ip0","pdp_ip1","pdp_ip2","pdp_ip3"]
                let name: String = String(cString: (interface.ifa_name))
                if  name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t((interface.ifa_addr.pointee.sa_len)), &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                    let isInURLFormat = address?.contains(".")
                    if  isInURLFormat!  {
                         break
                    }
                }
            }
        }
        freeifaddrs(ifaddr)
    }
    return address ?? "172.20.10.1" // this is the cellular ip address
}


struct CustomControl {
    var throttle: Float = 0
    var steering: Float = 0
    
    // Jerry
    var kp: Float = 0
    var ki: Float = 0
    var kd: Float = 0
    
    init() {
        self.throttle = 0
        self.steering = 0
        self.kp = 0
        self.ki = 0
        self.kd = 0
    }
    init(throttle: Float, steering: Float, kp: Float, ki: Float, kd: Float) {
        self.throttle = throttle.clamped(to: -1...1)
        self.steering = steering.clamped(to: -1...1)
        // Jerry
        self.kp = kp
        self.ki = ki
        self.kd = kd
    }
    
    public var description: String { return "\(throttle), \(steering), \(kp), \(ki), \(kd)" }
    
    public var data: Data {
        return self.description.data(using: .utf8)!
    }
}

class VehicleState {
//    var transform: CustomTransform = CustomTransform()
//    var velocity: SCNVector3 = SCNVector3(0,0,0)
    var x: Float = 0
    var y: Float = 0
    var z: Float = 0
    var roll: Float = 0
    var pitch: Float = 0
    var yaw: Float = 0
    var vx: Float = 0
    var vy: Float = 0
    var vz: Float = 0
    var ax: Float = 0
    var ay: Float = 0
    var az: Float = 0
    var gx: Float = 0
    var gy: Float = 0
    var gz: Float = 0
    var recv_time: Float = 0
    
    var hall_effect_sensor_velocity: Float = 0
    
    init() {
        
    }
    func toString() -> String {
        let string = "\(self.x), \(self.y), \(self.z), \(self.roll), \(self.pitch), \(self.yaw), \(self.vx),\(self.vy),\(self.vz),\(self.ax),\(self.ay),\(self.az),\(self.gx),\(self.gy),\(self.gz),\(hall_effect_sensor_velocity),\(self.recv_time)"
        return string
    }
    func toData() -> Data {
        return self.toString().data(using: String.Encoding.utf8)!
    }
    
//    func update(transform: CustomTransform, velocity: SCNVector3) {
//        self.transform = transform
//        self.velocity = velocity
//    }
    func update(x:Float, y:Float, z:Float,roll:Float,pitch:Float, yaw:Float, vx:Float, vy:Float, vz:Float, ax:Float, ay:Float, az:Float, gx:Float,gy:Float, gz:Float, recv_time: TimeInterval){
    self.x = x
    self.y = y
    self.z = z
    self.roll = roll
    self.pitch = pitch
    self.yaw = yaw
    self.vx = vx
    self.vy = vy
    self.vz = vz
    self.ax = ax
    self.ay = ay
    self.az = az
    self.gx = gx
    self.gy = gy
    self.gz = gz
    self.recv_time = Float(recv_time)
    }
}

class CustomTransform {
    var position: SCNVector3 = SCNVector3(0, 0, 0)
    var eulerAngle: SCNVector3 = SCNVector3(0,0,0)
    
    init() {
        
    }
    
    init(position: SCNVector3) {
        self.position = position
    }
    func toData() -> Data {
        let string = "\(position.x), \(position.y), \(position.z), \(eulerAngle.x), \(eulerAngle.y), \(eulerAngle.z)"
        return string.data(using: String.Encoding.utf8)!
    }
}

enum ImageRatioSettingsEnum{
    case twentyone_nine
    case four_three
    case sixteen_nine
    case no_cut
}

class CustomImage {
    var updating = false
    var uiImage: UIImage?
    var outputData: Data?
    var x: Int = 0;
    var y: Int = 0;
    var width: Int = 100;
    var height: Int = 100;
    var compQuality: CGFloat = 0.1;
    var cropRect: CGRect?
    var intrinsics: simd_float3x3 = simd_float3x3()
    var buffer:Int = 200;
    var ratio: ImageRatioSettingsEnum = .no_cut
    var circular = CircularBuffer<Data>(capacity: 5)
    
    

    init() {
        self.updateCropping(x: self.x, y: self.y, width: self.width, height: self.height)
    }
    init(compressionQuality:CGFloat = 0.1, ratio:ImageRatioSettingsEnum = .no_cut) {
        self.compQuality = compressionQuality
        self.ratio = ratio
    }
    init(x: Int, y: Int, width: Int, height: Int, compressionQuality:CGFloat = 0.1) {
        self.compQuality = compressionQuality
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.cropRect = CGRect(
            x: x,
            y: y,
            width: width,
            height: height
        ).integral
    }
    func updateCropping(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.cropRect = CGRect(
            x: x,
            y: y,
            width: width,
            height: height
        ).integral
    }
    func initializeCropRec(image:UIImage) {
        let size = image.size
        
        if self.ratio == .four_three {
            let width = 3 * Int(size.height) / 4
            let x = Int(size.width) - width - self.buffer
            self.updateCropping(x: x, y: 0, width: width, height:  Int(size.height))
        } else if self.ratio == .sixteen_nine {
            let width = 9 * Int(size.height) / 16
            let x = Int(size.width) - width - self.buffer
            self.updateCropping(x: x, y: 0, width: width, height:  Int(size.height))
        } else if self.ratio == .twentyone_nine {
            let width = 9 * Int(size.height) / 21
            let x = Int(size.width) - width - self.buffer
            self.updateCropping(x: x, y: 0, width: width, height:  Int(size.height))
        }
    }
    
    
    func cropImage(sourceImage: UIImage) -> UIImage {
        if self.cropRect == nil {
            self.initializeCropRec(image: sourceImage)
        }
        
        let sourceCGImage = sourceImage.cgImage!
        let croppedCGImage = sourceCGImage.cropping(to: self.cropRect!)
        return UIImage(
            cgImage: croppedCGImage!,
            scale: sourceImage.imageRendererFormat.scale,
            orientation: sourceImage.imageOrientation
        )
    }
    
    func updateImage(sourceImage: UIImage, rotation:Float=0.0){
        /*
         THIS FUNCTION IS DEPRECATED
         */
        self.updating = true
        if self.ratio == .no_cut {
            self.uiImage = sourceImage
            self.outputData = self.uiImage?.jpegData(compressionQuality: self.compQuality)
            } else {
            if self.cropRect == nil {
                self.initializeCropRec(image: sourceImage)
            }
            
            let sourceCGImage = sourceImage.cgImage!
            let croppedCGImage = sourceCGImage.cropping(to: self.cropRect!)
            if croppedCGImage != nil {
                self.uiImage = UIImage(
                    cgImage: croppedCGImage!,
                    scale: sourceImage.imageRendererFormat.scale,
                    orientation: sourceImage.imageOrientation
                )
            } else {
                print("Unable to update image because croppedCGImage is nil")
            }

            self.outputData = self.uiImage?.jpegData(compressionQuality: self.compQuality)
        }
        
        self.updating = false
    }
    
    func updateImage(cvPixelBuffer: CVPixelBuffer, rotation:Float=0.0) {
        if self.updating == false {
            self.updating = true
            let uiImage = UIImage(pixelBuffer: cvPixelBuffer)!
            let data = uiImage.jpegData(compressionQuality: 0.1)!
            self.circular.overwrite(data)
            self.updating = false
        }
    }
    
    func toJPEGData() -> Data? {
        if self.uiImage == nil {
            return nil
        } else {
            let data = autoreleasepool(invoking: { () -> Data? in
                return (self.uiImage!.jpegData(compressionQuality: self.compQuality))
            })
            return data
        }
    }
    func updateIntrinsics(intrinsics: simd_float3x3) {
        self.intrinsics = intrinsics
    }
}


extension Data {
    public static func from(pixelBuffer: CVPixelBuffer) -> Self {
        CVPixelBufferLockBaseAddress(pixelBuffer, [.readOnly])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, [.readOnly]) }

        // Calculate sum of planes' size
        var totalSize = 0
        for plane in 0 ..< CVPixelBufferGetPlaneCount(pixelBuffer) {
            let height      = CVPixelBufferGetHeightOfPlane(pixelBuffer, plane)
            let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, plane)
            let planeSize   = height * bytesPerRow
            totalSize += planeSize
        }

        guard let rawFrame = malloc(totalSize) else { fatalError() }
        var dest = rawFrame

        for plane in 0 ..< CVPixelBufferGetPlaneCount(pixelBuffer) {
            let source      = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, plane)
            let height      = CVPixelBufferGetHeightOfPlane(pixelBuffer, plane)
            let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, plane)
            let planeSize   = height * bytesPerRow

            memcpy(dest, source, planeSize)
            dest += planeSize
        }

        return Data(bytesNoCopy: rawFrame, count: totalSize, deallocator: .free)
    }
}

extension UIImage {
    public convenience init?(pixelBuffer: CVPixelBuffer) {
        var cgImage: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)
        
        guard let cgImage = cgImage else {return nil}
        
        self.init(cgImage: cgImage)
    }
}

class CustomDepthData {
    var updating = false
    var width = 256
    var height = 192
    var depth_data:Data! = nil
    var ar_depth_data: ARDepthData! = nil
    var fxD: Float? = nil
    var fyD: Float? = nil
    var cxD: Float? = nil
    var cyD: Float? = nil
    var circular: CircularBuffer = CircularBuffer<Data>(capacity: 5)
    
    func update(frame: ARFrame) {
        if self.updating == false {
            self.updating = true
            let data = frame.sceneDepth!
            let cam = frame.camera
            self.ar_depth_data = data
            let depth_data = self.depthCVPixelToData(from: data.depthMap)
            self.circular.overwrite(depth_data)
            self.updateIntrinsics(rgb_x: Float(cam.imageResolution.height),
                                  rgb_y: Float(cam.imageResolution.width),
                                  rgb_fx: cam.intrinsics[0][0],
                                  rgb_fy: cam.intrinsics[1][1],
                                  rgb_cx: cam.intrinsics[2][0],
                                  rgb_cy: cam.intrinsics[2][1])
            self.updating = false
        }
        
    }
    
    func updateIntrinsics(rgb_x:Float, rgb_y:Float, rgb_fx: Float, rgb_fy: Float, rgb_cx:Float, rgb_cy: Float) {
        let y = Float(self.width)
        let x = Float(self.height)
        self.fxD = x / rgb_x * rgb_fx
        self.fyD = y / rgb_y * rgb_fy
        self.cxD = x / rgb_x * rgb_cx
        self.cyD = y / rgb_y * rgb_cy
//        self.fxD = rgb_fx
//        self.fyD = rgb_fy
//        self.cxD = rgb_cx
//        self.cyD = rgb_cy
    }
    
    func depthCVPixelToData(from pixelBuffer: CVPixelBuffer) -> Data {
        
        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        
        self.height = CVPixelBufferGetHeight(pixelBuffer)
        self.width = CVPixelBufferGetWidth(pixelBuffer)
        var data = Data()
        let yBaseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)
        let yBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let yLength = yBytesPerRow * self.height
        data.append(Data(bytes: yBaseAddress!, count: yLength))
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        
        return data
    }
}


// MARK: SCN Vector
public extension SCNVector3
{
    /**
     * Negates the vector described by SCNVector3 and returns
     * the result as a new SCNVector3.
     */
    func negate() -> SCNVector3 {
        return self * -1
    }
    
    /**
     * Negates the vector described by SCNVector3
     */
    mutating func negated() -> SCNVector3 {
        self = negate()
        return self
    }
    
    /**
     * Returns the length (magnitude) of the vector described by the SCNVector3
     */
    func length() -> Float {
        return sqrtf(x*x + y*y + z*z)
    }
    
    /**
     * Normalizes the vector described by the SCNVector3 to length 1.0 and returns
     * the result as a new SCNVector3.
     */
    func normalized() -> SCNVector3 {
        return self / length()
    }
    
    /**
     * Normalizes the vector described by the SCNVector3 to length 1.0.
     */
    mutating func normalize() -> SCNVector3 {
        self = normalized()
        return self
    }
    
    /**
     * Calculates the distance between two SCNVector3. Pythagoras!
     */
    func distance(vector: SCNVector3) -> Float {
        return (self - vector).length()
    }
    
    /**
     * Calculates the dot product between two SCNVector3.
     */
    func dot(vector: SCNVector3) -> Float {
        return x * vector.x + y * vector.y + z * vector.z
    }
    
    /**
     * Calculates the cross product between two SCNVector3.
     */
    func cross(vector: SCNVector3) -> SCNVector3 {
        return SCNVector3Make(y * vector.z - z * vector.y, z * vector.x - x * vector.z, x * vector.y - y * vector.x)
    }
}

/**
 * Adds two SCNVector3 vectors and returns the result as a new SCNVector3.
 */
public func + (left: SCNVector3, right: SCNVector3) -> SCNVector3 {
    return SCNVector3Make(left.x + right.x, left.y + right.y, left.z + right.z)
}

/**
 * Increments a SCNVector3 with the value of another.
 */
public func += ( left: inout SCNVector3, right: SCNVector3) {
    left = left + right
}

/**
 * Subtracts two SCNVector3 vectors and returns the result as a new SCNVector3.
 */
public func - (left: SCNVector3, right: SCNVector3) -> SCNVector3 {
    return SCNVector3Make(left.x - right.x, left.y - right.y, left.z - right.z)
}

/**
 * Decrements a SCNVector3 with the value of another.
 */
public func -= ( left: inout SCNVector3, right: SCNVector3) {
    left = left - right
}

/**
 * Multiplies two SCNVector3 vectors and returns the result as a new SCNVector3.
 */
public func * (left: SCNVector3, right: SCNVector3) -> SCNVector3 {
    return SCNVector3Make(left.x * right.x, left.y * right.y, left.z * right.z)
}

/**
 * Multiplies a SCNVector3 with another.
 */
public func *= ( left: inout SCNVector3, right: SCNVector3) {
    left = left * right
}

/**
 * Multiplies the x, y and z fields of a SCNVector3 with the same scalar value and
 * returns the result as a new SCNVector3.
 */
public func * (vector: SCNVector3, scalar: Float) -> SCNVector3 {
    return SCNVector3Make(vector.x * scalar, vector.y * scalar, vector.z * scalar)
}

/**
 * Multiplies the x and y fields of a SCNVector3 with the same scalar value.
 */
public func *= ( vector: inout SCNVector3, scalar: Float) {
    vector = vector * scalar
}

/**
 * Divides two SCNVector3 vectors abd returns the result as a new SCNVector3
 */
public func / (left: SCNVector3, right: SCNVector3) -> SCNVector3 {
    return SCNVector3Make(left.x / right.x, left.y / right.y, left.z / right.z)
}

/**
 * Divides a SCNVector3 by another.
 */
public func /= ( left: inout SCNVector3, right: SCNVector3) {
    left = left / right
}

/**
 * Divides the x, y and z fields of a SCNVector3 by the same scalar value and
 * returns the result as a new SCNVector3.
 */
public func / (vector: SCNVector3, scalar: Float) -> SCNVector3 {
    return SCNVector3Make(vector.x / scalar, vector.y / scalar, vector.z / scalar)
}

/**
 * Divides the x, y and z of a SCNVector3 by the same scalar value.
 */
public func /= ( vector: inout SCNVector3, scalar: Float) {
    vector = vector / scalar
}

/**
 * Negate a vector
 */
public func SCNVector3Negate(vector: SCNVector3) -> SCNVector3 {
    return vector * -1
}

/**
 * Returns the length (magnitude) of the vector described by the SCNVector3
 */
public func SCNVector3Length(vector: SCNVector3) -> Float
{
    return sqrtf(vector.x*vector.x + vector.y*vector.y + vector.z*vector.z)
}

/**
 * Returns the distance between two SCNVector3 vectors
 */
public func SCNVector3Distance(vectorStart: SCNVector3, vectorEnd: SCNVector3) -> Float {
    return SCNVector3Length(vector: vectorEnd - vectorStart)
}

/**
 * Returns the distance between two SCNVector3 vectors
 */
public func SCNVector3Normalize(vector: SCNVector3) -> SCNVector3 {
    return vector / SCNVector3Length(vector: vector)
}

/**
 * Calculates the dot product between two SCNVector3 vectors
 */
public func SCNVector3DotProduct(left: SCNVector3, right: SCNVector3) -> Float {
    return left.x * right.x + left.y * right.y + left.z * right.z
}

/**
 * Calculates the cross product between two SCNVector3 vectors
 */
public func SCNVector3CrossProduct(left: SCNVector3, right: SCNVector3) -> SCNVector3 {
    return SCNVector3Make(left.y * right.z - left.z * right.y, left.z * right.x - left.x * right.z, left.x * right.y - left.y * right.x)
}

/**
 * Calculates the SCNVector from lerping between two SCNVector3 vectors
 */
public func SCNVector3Lerp(vectorStart: SCNVector3, vectorEnd: SCNVector3, t: Float) -> SCNVector3 {
    return SCNVector3Make(vectorStart.x + ((vectorEnd.x - vectorStart.x) * t), vectorStart.y + ((vectorEnd.y - vectorStart.y) * t), vectorStart.z + ((vectorEnd.z - vectorStart.z) * t))
}

/**
 * Project the vector, vectorToProject, onto the vector, projectionVector.
 */
public func SCNVector3Project(vectorToProject: SCNVector3, projectionVector: SCNVector3) -> SCNVector3 {
    let scale: Float = SCNVector3DotProduct(left: projectionVector, right: vectorToProject) / SCNVector3DotProduct(left: projectionVector, right: projectionVector)
    let v: SCNVector3 = projectionVector * scale
    return v
}
func rad2deg(_ number: Double) -> Double {
    return number * 180 / .pi
}
func deg2rad(_ number: Double) -> Double {
    return number * .pi / 180
}


extension Date {
    static var currentTimeStamp: Int64{
        return Int64(Date().timeIntervalSince1970 * 1000)
    }
}

extension CGFloat {
    func map(from: ClosedRange<CGFloat>, to: ClosedRange<CGFloat>) -> CGFloat {
        let result = ((self - from.lowerBound) / (from.upperBound - from.lowerBound)) * (to.upperBound - to.lowerBound) + to.lowerBound
        return result
    }
    func toString() -> String {
        return String(format: "%.0f", Int(self))
    }
    //test
}



extension float4x4 {
    /**
     Treats matrix as a (right-hand column-major convention) transform matrix
     and factors out the translation component of the transform.
    */
    var translation: SIMD3<Float> {
        get {
            let translation = columns.3
            return [translation.x, translation.y, translation.z]
        }
        set(newValue) {
            columns.3 = [newValue.x, newValue.y, newValue.z, columns.3.w]
        }
    }
    
    /**
     Factors out the orientation component of the transform.
    */
    var orientation: simd_quatf {
        return simd_quaternion(self)
    }
    
    /**
     Creates a transform matrix with a uniform scale factor in all directions.
     */
    init(uniformScale scale: Float) {
        self = matrix_identity_float4x4
        columns.0.x = scale
        columns.1.y = scale
        columns.2.z = scale
    }
}

// MARK: - CGPoint extensions

extension CGPoint {
    /// Extracts the screen space point from a vector returned by SCNView.projectPoint(_:).
    init(_ vector: SCNVector3) {
        self.init(x: CGFloat(vector.x), y: CGFloat(vector.y))
    }

    /// Returns the length of a point when considered as a vector. (Used with gesture recognizers.)
    var length: CGFloat {
        return sqrt(x * x + y * y)
    }
}

func validateIpAddress(ipToValidate: String) -> Bool {

    var sin = sockaddr_in()
    var sin6 = sockaddr_in6()

    if ipToValidate.withCString({ cstring in inet_pton(AF_INET6, cstring, &sin6.sin6_addr) }) == 1 {
        // IPv6 peer.
        return true
    }
    else if ipToValidate.withCString({ cstring in inet_pton(AF_INET, cstring, &sin.sin_addr) }) == 1 {
        // IPv4 peer.
        return true
    }

    return false;
}


protocol ScanQRCodeProtocol {
    func onQRCodeScanFinished() 
}

// Put this piece of code anywhere you like
extension UIViewController {
    func hideKeyboardWhenTappedAround() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(UIViewController.dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }
    
    @objc func dismissKeyboard() {
        view.endEditing(true)
    }
}


class CircularBuffer<T> {
    let capacity: Int
    var buffer = [T]()
    
    init(capacity: Int) {
        self.capacity = capacity
    }
    
    func write(_ element: T) throws {
        guard buffer.count < capacity else {
            throw CircularBufferError.bufferFull
        }
        buffer.append(element)
    }
    
    func read() throws -> T {
        guard !buffer.isEmpty else {
            throw CircularBufferError.bufferEmpty
        }
        return buffer.removeFirst()
    }
    
    func clear() {
        buffer = [T]()
    }
    
    func overwrite(_ element: T) {
        if buffer.count < capacity {
            try? write(element)
        } else {
            _ = buffer.removeLast()
            buffer.append(element)
        }
    }
}
enum CircularBufferError: Error {
    case bufferEmpty
    case bufferFull
}


