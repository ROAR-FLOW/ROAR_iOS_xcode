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


class CaliberationViewController: UIViewController {
    @IBOutlet weak var bleButton: UIButton!
    @IBOutlet weak var sendControlBtn: UIButton!
    @IBOutlet weak var sendKValuesBtn: UIButton!
    @IBOutlet weak var requestBLENameChangeButton: UIButton!
    @IBOutlet weak var newBLENameTextField: UITextField!
    @IBOutlet weak var throttleTextField: UITextField!
    @IBOutlet weak var SteeringTextField: UITextField!
    @IBOutlet weak var KpTextField: UITextField!
    @IBOutlet weak var KiTextField: UITextField!
    @IBOutlet weak var KdTextField: UITextField!
    @IBOutlet weak var velocity_label: UILabel!
    var bluetoothPeripheral: CBPeripheral!
    var centralManager: CBCentralManager!
    
    var logger: SwiftyBeaver.Type {return (UIApplication.shared.delegate as! AppDelegate).logger}

    var ThrottleControllerRange: ClosedRange<CGFloat> = CGFloat(-5.0)...CGFloat(5.0);
    var SteeringControllerRange: ClosedRange<CGFloat> = CGFloat(-1.0)...CGFloat(1.0);
    let throttle_range = CGFloat(1000)...CGFloat(2000)
    let steer_range = CGFloat(1000)...CGFloat(2000)
    var bleTimer: Timer!
    var bluetoothDispatchWorkitem:DispatchWorkItem!
    var bleControlCharacteristic: CBCharacteristic!
    var velocityCharacteristic: CBCharacteristic!
//    var throtReturnCharacteristic: CBCharacteristic!
    var configCharacteristic: CBCharacteristic!
    var newNameCharacteristic: CBCharacteristic!
    var velocity: Float = 0
    
    var readVelocityTimer: Timer!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.hideKeyboardWhenTappedAround() 
        self.centralManager = CBCentralManager(delegate: self, queue: nil)
        self.bleTimer = Timer.scheduledTimer(timeInterval: 2, target: self, selector: #selector(autoReconnectBLE), userInfo: nil, repeats: true)
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
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
        self.readVelocityTimer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(self.readVelocity), userInfo: nil, repeats: true)
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
        // if ble is connected, use legacy method to send ble values
        if self.bluetoothPeripheral != nil && self.configCharacteristic != nil {
            self.writeToBluetoothDevice(throttle: throttle, steering: steering)
            Loaf.init("\(throttle),\(steering) sent", state: .success, location: .bottom, presentingDirection: .vertical, dismissingDirection: .vertical, sender: self).show()
        } else {
            Loaf.init("Unable to send", state: .error, location: .bottom, presentingDirection: .vertical, dismissingDirection: .vertical, sender: self).show()
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
}
