//
//  CaliberationViewController.swift
//  ROAR
//
//  Created by Michael Wu on 2/9/22.
//

import Foundation
import UIKit
import CoreBluetooth
import SwiftyBeaver
import Loaf
import TabularData
import ARKit
class CaliberationViewController: UIViewController {
    @IBOutlet weak var bleButton: UIButton!
    @IBOutlet weak var sendControlBtn: UIButton!
    @IBOutlet weak var sendKValuesBtn: UIButton!
    @IBOutlet weak var requestBLENameChangeButton: UIButton!
    @IBOutlet weak var newBLENameTextField: UITextField!
    @IBOutlet weak var cali_AR: ARSCNView!
    @IBOutlet weak var throttleTextField: UITextField!
    @IBOutlet weak var SteeringTextField: UITextField!
    @IBOutlet weak var KpTextField: UITextField!
    @IBOutlet weak var KiTextField: UITextField!
    @IBOutlet weak var KdTextField: UITextField!
    @IBOutlet weak var velocity_label: UILabel!
//    @IBOutlet weak var throt_return_label: UILabel!
//    var controlCenter: ControlCenter!
    public var backCamImage: CustomImage!
    public var worldCamDepth: CustomDepthData!
    var bluetoothPeripheral: CBPeripheral!
    var centralManager: CBCentralManager!
    
    var logger: SwiftyBeaver.Type {return (UIApplication.shared.delegate as! AppDelegate).logger}
    public var transform: CustomTransform = CustomTransform()
    var ThrottleControllerRange: ClosedRange<CGFloat> = CGFloat(-5.0)...CGFloat(5.0);
    var SteeringControllerRange: ClosedRange<CGFloat> = CGFloat(-1.0)...CGFloat(1.0);
    let throttle_range = CGFloat(1000)...CGFloat(2000)
    let steer_range = CGFloat(1000)...CGFloat(2000)
    var bleTimer: Timer!
    var bluetoothDispatchWorkitem:DispatchWorkItem!
    var bleControlCharacteristic: CBCharacteristic!
    var velocityCharacteristic: CBCharacteristic!
    var throtReturnCharacteristic: CBCharacteristic!
    var configCharacteristic: CBCharacteristic!
    var newNameCharacteristic: CBCharacteristic!
    var velocity: Double = 0
    var throtReturn: Float = 0
    private var prevTransformUpdateTime: TimeInterval?;
    var readVelocityTimer: Timer!
    var start_time: Double = 0
    var current_time: Double = 0
    var current_location: Double = -32.0 / 16
    var distance_error_current: Double = 0
    var distance_error_before: Double = 0
    var distance_error_integral: Double = 0
    var result: DataFrame = [:]
    var rowIndex: Int = 0
    var run_program: Bool = false
    
    public var fileName = "data.csv";
    public var dataArray : [String] = []
    public var tmpArrayValue = String();
    public var dataHasWritten = false;
    public var pidHasWritten = false;
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.hideKeyboardWhenTappedAround()
        self.backCamImage = CustomImage(compressionQuality: 0.005, ratio: .no_cut)//AppInfo.imageRatio)
        self.worldCamDepth = CustomDepthData()
        if let mapData = UserDefaults.standard.value(forKey: AppInfo.get_ar_experience_name()) as? Data {
            if let map = loadMap(data: mapData) {
                self.startARSession(worldMap: map, worldOriginTransform: nil)
            } else {
                self.startARSession(worldMap: nil, worldOriginTransform: nil)
            }
        } else {
            self.startARSession(worldMap: nil, worldOriginTransform: nil)
        }
        self.centralManager = CBCentralManager(delegate: self, queue: nil)
        self.bleTimer = Timer.scheduledTimer(timeInterval: 2, target: self, selector: #selector(autoReconnectBLE), userInfo: nil, repeats: true)
        let url = Bundle.main.url(forResource: "final_deliver", withExtension: "csv")!
        let df = try! DataFrame(contentsOfCSVFile: url)
        self.result = df.selecting(columnNames: ["PassedTime","DiffDistance"])
        self.rowIndex = 0
        
        
        let csvHeader = "time,velocity,location,loc_followed,distance,error,kp,ki,kd\n"
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd_HH-mm-ss"
        let dateString = formatter.string(from: Date())
        self.fileName =  "flow_data_"+dateString+".csv"
        createCSV(text: csvHeader, toDirectory: self.getDocumentDirectory(), withFileName: fileName)
        
        
        
        
    }
    
    func loadMap(data:Data) -> ARWorldMap? {
        do {
            guard let worldMap = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data) else { return nil }
            return worldMap
        } catch {
            return nil
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        guard let filePath = self.append(toPath: self.getDocumentDirectory(),
                                         withPathComponent: self.fileName) else {
                                            return
        }
        
        if FileManager.default.fileExists(atPath: filePath) {
            if let fileHandle = try? FileHandle(forWritingAtPath: filePath) {
                 fileHandle.seekToEndOfFile()
                dataArray.forEach{ tmp in
                    guard let tmpData = tmp.data(using: String.Encoding.utf8) else {return}
                    fileHandle.write(tmpData)
                }
                 fileHandle.closeFile()
             }
        }
        
        
    }
    
    @objc func autoReconnectBLE() {
        if AppInfo.sessionData.isBLEConnected == false {
            self.onBLEDisconnected()
            self.logger.info("BLE is disconnected state. Attempting to reconnect...")
            self.centralManager.scanForPeripherals(withServices: nil, options: nil)
        }
    }
    
    func onBLEConnected() {
        self.bleButton.setTitleColor(.green, for: .normal)
        self.bleButton.setTitle("BLE: \(AppInfo.bluetootConfigurations?.name ?? "No Name")", for: .normal)
        AppInfo.save()
        self.readVelocityTimer = Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(self.readVelocity), userInfo: nil, repeats: true)
    }
    
    func onBLEDisconnected() {
        self.bleButton.setTitleColor(.red, for: .normal)
        self.bleButton.setTitle("BLE Not Connected", for: .normal)
        if self.readVelocityTimer != nil {
            self.readVelocityTimer.invalidate()
        }
        
    }
    @IBAction func onSendControlBtnTapped(_ sender: UIButton) {
        // First extract throttle and steering values from text field and cast it into CGFloat
        let throttle = CGFloat(Float(self.throttleTextField.text ?? "0") ?? 0)
        let steering = CGFloat(Float(self.SteeringTextField.text ?? "0") ?? 0)
        let start_time = TimeInterval(NSDate().timeIntervalSince1970)
        self.start_time = start_time
        if throttle != 0 {
            self.run_program = true
        } else {
            self.run_program = false
        }
        startWritingToBLE(steering: steering)
        
    }
    
    func startWritingToBLE(steering: CGFloat) {
        DispatchQueue.global(qos: .background).async {
            self.bleTimer = Timer(timeInterval: 0.1, repeats: true) { [self] _ in
                    // TODO reconnect every 5 seconds
                    if AppInfo.sessionData.isBLEConnected {
                        var throttle = Double(0)
                        //change the total running time here
                        if self.run_program && rowIndex <= 2300 {
                            self.current_time += 0.1
                            self.current_location = 0.1 * self.velocity + self.current_location
                            
                            //get from csv about followed car's location
                            // DistanceGPS
                            let target_error = 16.0 / 16
                            let followed_location = (result[row:self.rowIndex][1]! as! Double) / 16
                            print("location:\(followed_location)")
                            print("current_car_location:\(self.current_location)")
                        
                            
                            self.rowIndex = self.rowIndex + 1
                            //current_location originally -10,followed start from 0
                            self.distance_error_current = (followed_location - self.current_location) - target_error
                            let d_error = (-self.distance_error_current + self.distance_error_before) / 0.1
                            print("de\(d_error)")
                            self.distance_error_integral += self.distance_error_current * 0.1
                            
                            self.distance_error_before = self.distance_error_current
                            
                            print("error:\(distance_error_current)")
                            let kp = 5.0
                            let ki = 0.0
                            let kd = 0.15
                            //throttle is target speed
                            throttle = kp * self.distance_error_current + kd * d_error + ki * self.distance_error_integral
                            if throttle > 5{
                                throttle = 3.0
                            }
                            if (throttle < -5.0) {
                                throttle = -5.0
                            }
                            let distance = followed_location - self.current_location
                          
                            
                            // // let csvHeader = "time,velocity,location,loc_followed,distance,error,kp,ki,kd\n"
                            self.tmpArrayValue = "\(self.current_time),\(self.velocity),\(self.current_location),\(followed_location),\(distance),\(self.distance_error_current),\(kp), \(ki),\(kd)\n"
                            self.dataArray.append(tmpArrayValue)
                        }else {
                            throttle = 0.0
                        }
                        if self.bluetoothPeripheral != nil && self.configCharacteristic != nil {
                            self.writeToBluetoothDevice(throttle: throttle, steering: steering)
                        }
                    }
                }
                let runLoop = RunLoop.current
                runLoop.add(self.bleTimer, forMode: .default)
                runLoop.run()
            }
    }
    
    @IBAction func onBLENameChangeBtn(_ sender: UIButton) {
        let blename_str = self.newBLENameTextField.text ?? "0"
        self.sendBLENewName(peripheral: self.bluetoothPeripheral, message: blename_str)
    }
    
    @IBAction func onSendKValuesTapped(_ sender: UIButton) {
        // First extract k values from text field and cast it into float
        var kp = Float(self.KpTextField.text ?? "1") ?? 1
        var kd = Float(self.KdTextField.text ?? "1") ?? 1
        var ki = Float(self.KiTextField.text ?? "1") ?? 1
        
        
        // if BLE is connected, send the K values by turning them into little endian float.
        if self.bluetoothPeripheral != nil && self.configCharacteristic != nil {
            var data = Data()
            withUnsafePointer(to: &kp) { data.append(UnsafeBufferPointer(start: $0, count: 1)) }
            withUnsafePointer(to: &kd) { data.append(UnsafeBufferPointer(start: $0, count: 1)) }
            withUnsafePointer(to: &ki) { data.append(UnsafeBufferPointer(start: $0, count: 1)) }
            self.bluetoothPeripheral.writeValue(data, for: configCharacteristic, type:.withoutResponse)
            Loaf.init("\(kp),\(kd),\(ki) sent", state: .success, location: .bottom, presentingDirection: .vertical, dismissingDirection: .vertical, sender: self).show()

        } else {
            Loaf.init("Unable to send", state: .error, location: .bottom, presentingDirection: .vertical, dismissingDirection: .vertical, sender: self).show()
        }
    }
    
    private func getDocumentDirectory() -> String {
        let documentDirectory = NSSearchPathForDirectoriesInDomains(.documentDirectory,
                                                                    .userDomainMask,
                                                                    true)
        return documentDirectory[0]
    }
    
    private func append(toPath path: String,
                        withPathComponent pathComponent: String) -> String? {
        if var pathURL = URL(string: path) {
            pathURL.appendPathComponent(pathComponent)
            
            return pathURL.absoluteString
        }
        
        return nil
    }
    
    private func createCSV(text: String,
                      toDirectory directory: String,
                      withFileName fileName: String) {
        guard let filePath = self.append(toPath: directory,
                                         withPathComponent: fileName) else {
            return
        }
        
        do {
            try text.write(toFile: filePath,
                           atomically: true,
                           encoding: .utf8)
        } catch {
            print("Error", error)
            return
        }
        
        print("Save successful")
    }
    
    private func printCSV(fromDocumentsWithFileName fileName: String) {
        guard let filePath = self.append(toPath: self.getDocumentDirectory(),
                                         withPathComponent: fileName) else {
                                            return
        }
        
        do {
            let savedString = try String(contentsOfFile: filePath)
            
            print(savedString)
        } catch {
            print("Error reading saved file")
        }
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
            
            
            self.transform.position = node.position
            
            // yaw, roll, pitch DO NOT CHANGE THIS!
            self.transform.eulerAngle = SCNVector3(node.eulerAngles.z, node.eulerAngles.y, node.eulerAngles.x)
            prevTransformUpdateTime = time
        }
    }
    
}
