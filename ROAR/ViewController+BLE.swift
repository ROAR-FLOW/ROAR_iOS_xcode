//
//  ViewController+BLE.swift
//  ROAR
//
//  Created by Michael Wu on 9/11/21.
//

import Foundation
import CoreBluetooth
import UIKit
import Loaf
extension ViewController:CBCentralManagerDelegate, CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let services = peripheral.services {
            for service in services {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .unknown:
            self.logger.error("central.state is .unknown")
        case .resetting:
            self.logger.error("central.state is .resetting")
        case .unsupported:
            self.logger.error("central.state is .unsupported")
        case .unauthorized:
            self.logger.error("central.state is .unauthorized")
        case .poweredOff:
            self.logger.error("central.state is .poweredOff")
        case .poweredOn:
            self.logger.info("central.state is .poweredOn, Scanning for peripherals")
            self.centralManager.scanForPeripherals(withServices: nil, options: nil)
        @unknown default:
            self.logger.error("unknown state encountered")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if peripheral.identifier == AppInfo.bluetootConfigurations?.uuid{
            self.logger.info("Peripheral found \(AppInfo.bluetootConfigurations?.name ?? "No Name")")
            self.bluetoothPeripheral = peripheral
            centralManager.stopScan()
            centralManager.connect(peripheral, options: nil)
        }
    }
    
    func centralManager(_ central: CBCentralManager, connectionEventDidOccur event: CBConnectionEvent, for peripheral: CBPeripheral) {
        self.logger.info("Connection event occured")
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices(nil)
        self.logger.info("Connected to \(AppInfo.bluetootConfigurations?.name ?? "No Name")")
        self.onBLEConnected()
        AppInfo.sessionData.isBLEConnected = true
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        self.logger.info("failed to connect")
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        self.logger.info("Disconnected : \(AppInfo.bluetootConfigurations?.name ?? "No Name")")
        self.onBLEDisconnected()
        AppInfo.sessionData.isBLEConnected = false
    }
    
    func startWritingToBLE() {
        DispatchQueue.global(qos: .background).async {
            self.bleTimer = Timer(timeInterval: 0.01, repeats: true) { _ in
                    // TODO reconnect every 5 seconds
                    if AppInfo.sessionData.isBLEConnected {
                        self.writeBLE()
                        self.readFromBLE()
                    }
                }
                let runLoop = RunLoop.current
                runLoop.add(self.bleTimer, forMode: .default)
                runLoop.run()
            }
    }
    
    func readFromBLE() {
        if velocityCharacteristic != nil {
            self.bluetoothPeripheral.readValue(for: self.velocityCharacteristic)
        }
    }
    func disconnectBluetooth() {
        self.bleTimer.invalidate()
        if self.bluetoothPeripheral != nil {
            self.centralManager.cancelPeripheralConnection(self.bluetoothPeripheral)
        }
    }
    
    func writeBLE() {
        if self.bluetoothPeripheral != nil && self.bluetoothPeripheral.state == .connected {
            self.writeToBluetoothDevice(
                throttle: CGFloat(controlCenter.control.throttle),
                steering: CGFloat(controlCenter.control.steering),
                kp: CGFloat(controlCenter.control.kp),
                ki: CGFloat(controlCenter.control.ki),
                kd: CGFloat(controlCenter.control.kd)
            )
        }
    }
    func writeToBluetoothDevice(throttle: CGFloat, steering: CGFloat, kp: CGFloat, ki: CGFloat, kd: CGFloat){
        let currThrottleRPM = throttle.map(from: self.iOSControllerRange, to: self.throttle_range)
        var currSteeringRPM = steering.map(from: self.iOSControllerRange, to: self.steer_range)
        
        // Jerry
        var currKp = kp
        var currKi = ki
        var currKd = kd
        
        currSteeringRPM = currSteeringRPM.clamped(to: 1000...2000)
        
        
        let message: String = "(" + String(Int(currThrottleRPM)) + "," + String(Int(currSteeringRPM)) + ")"
        if self.bluetoothPeripheral != nil {
            sendMessage(peripheral: self.bluetoothPeripheral, message: message)
        }
        
        // Jerry: Send kp, ki, kd to bluetooth
        // if BLE is connected, send the K values by turning them into little endian float.
        if self.bluetoothPeripheral != nil && self.bleControlCharacteristic != nil {
            var data = Data()
            withUnsafePointer(to: &currKp) { data.append(UnsafeBufferPointer(start: $0, count: 1)) }
            withUnsafePointer(to: &currKi) { data.append(UnsafeBufferPointer(start: $0, count: 1)) }
            withUnsafePointer(to: &currKd) { data.append(UnsafeBufferPointer(start: $0, count: 1)) }
            self.bluetoothPeripheral.writeValue(data, for: self.bleControlCharacteristic, type:.withoutResponse)
//            Loaf.init("\(kp),\(kd),\(ki) sent", state: .success, location: .bottom, presentingDirection: .vertical, dismissingDirection: .vertical, sender: self).show()
            print("send successfully")

        } else {
//            Loaf.init("Unable to send", state: .error, location: .bottom, presentingDirection: .vertical, dismissingDirection: .vertical, sender: self).show()
            print("Unable to send")
        }
    }
    
    func sendMessage(peripheral: CBPeripheral, message: String) {
        if bleControlCharacteristic != nil {
            peripheral.writeValue(message.data(using: .utf8)!, for: bleControlCharacteristic, type: .withoutResponse)
        }
        
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let characteristics = service.characteristics {
            for char in characteristics {
                if char.uuid.uuidString == "19B10011-E8F2-537E-4F6C-D104768A1214" {
                    bleControlCharacteristic = char
                }
                if char.uuid.uuidString == "19B10011-E8F2-537E-4F6C-D104768A1215" {
                    velocityCharacteristic = char
                }
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let e = error {
                print("ERROR didUpdateValue \(e)")
                return
            }
        if characteristic == velocityCharacteristic {
            guard let data = characteristic.value else { return }
            let velocity = data.withUnsafeBytes { $0.load(as: Float.self) }
            self.controlCenter.vehicleState.hall_effect_sensor_velocity = velocity
        }
    }
    
}
