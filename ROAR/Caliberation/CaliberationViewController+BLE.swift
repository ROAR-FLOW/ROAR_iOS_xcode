//
//  CaliberationViewController+BLE.swift
//  ROAR
//
//  Created by Michael Wu on 2/9/22.
//

import Foundation
import CoreBluetooth
import UIKit
extension CaliberationViewController:CBCentralManagerDelegate, CBPeripheralDelegate {
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
    
    @objc
    func readVelocity() {
        if throtReturnCharacteristic != nil {
            self.bluetoothPeripheral.readValue(for: self.throtReturnCharacteristic)
        }
    }
    func disconnectBluetooth() {
        self.bleTimer.invalidate()
        if self.bluetoothPeripheral != nil {
            self.centralManager.cancelPeripheralConnection(self.bluetoothPeripheral)
        }
    }
    
    func writeToBluetoothDevice(throttle: CGFloat, steering: CGFloat){
        // turn CGFloat into Int, and then into a string in format of (THROTTLE, STEERING) to send it.
        let currThrottleRPM = throttle.map(from: self.ThrottleControllerRange, to: self.throttle_range)
        var currSteeringRPM = steering.map(from: self.SteeringControllerRange, to: self.steer_range)
        
        currSteeringRPM = currSteeringRPM.clamped(to: 1000...2000)
        
        
        let message: String = "(" + String(Int(currThrottleRPM)) + "," + String(Int(currSteeringRPM)) + ")"
        if self.bluetoothPeripheral != nil {
            sendMessage(peripheral: self.bluetoothPeripheral, message: message)
        }
    }
    
    func sendMessage(peripheral: CBPeripheral, message: String) {
        if bleControlCharacteristic != nil {
            peripheral.writeValue(message.data(using: .utf8)!, for: bleControlCharacteristic, type: .withoutResponse)
        }
        
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let characteristics = service.characteristics {
            // catch and record all ble characteristics
            for char in characteristics {
                if char.uuid.uuidString == "19B10011-E8F2-537E-4F6C-D104768A1214" {
                    bleControlCharacteristic = char
                }
                if char.uuid.uuidString == "19B10011-E8F2-537E-4F6C-D104768A1215" {
                    velocityCharacteristic = char
                }
                if char.uuid.uuidString == "19B10012-E8F2-537E-4F6C-D104768A1214" {
                    newNameCharacteristic = char
                }
                if char.uuid.uuidString == "19B10011-E8F2-537E-4F6C-D104768A1216" {
                    configCharacteristic = char 
                }
                if char.uuid.uuidString == "19B10011-E8F2-537E-4F6C-D104768A1217" {
                    throtReturnCharacteristic = char
                }
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
//        print("Hei Hei Hei Hei Hei")
//        print(characteristic)
        if let e = error {
                print("ERROR didUpdateValue \(e)")
                return
            }
//        if characteristic == velocityCharacteristic {
//            // catch a velocity change and update the velocity label
//            guard let data = characteristic.value else { return }
//            self.velocity = data.withUnsafeBytes { $0.load(as: Float.self) }
//            DispatchQueue.main.async {
//                self.velocity_label.text = "Current Velocity: \(self.velocity)"
//            }
//        }

        if characteristic == throtReturnCharacteristic {
//            // catch a throttle change and update the throttle label
//            guard let throt = characteristic.value else { return }
//            self.throtReturn = throt.withUnsafeBytes { $0.load(as: Float.self) }
////            print("the returned throttle is: \(self.throtReturn)")
//            DispatchQueue.main.async {
//                self.throt_return_label.text = "Current throttle: \(self.throtReturn)"
//        }
//            print("hahahahahahahahahahahah")
            var throttle_float: Float = 0.2
            var velocity_float: Float = -0.2

            guard var data = characteristic.value else { return }
            print("Raw Data")
            print(data as NSData)

            withUnsafePointer(to: &throttle_float) { data.append(UnsafeBufferPointer(start: $0, count: 1)) }
            withUnsafePointer(to: &velocity_float) { data.append(UnsafeBufferPointer(start: $0, count: 1)) }
            
            let velocity_decoded: Float = data.withUnsafeBytes {
                $0.load(fromByteOffset: 0, as: Float.self)
            }
            let throttle_decoded: Float = data.withUnsafeBytes {
                $0.load(fromByteOffset: 4, as: Float.self)
            }
            
            print("Throttle initialized is \(throttle_float) throttle after decoded \(throttle_decoded).")
            print("Velocity initialized is \(velocity_float) Velocity after decoded \(velocity_decoded).")
//            self.controlCenter.vehicleState.hall_effect_sensor_velocity = velocity_decoded
//            self.controlCenter.vehicleState.car_throttle = throttle_decoded
            print("throttle decoded is:\(throttle_decoded)")
//            DispatchQueue.main.async {
//                self.throt_return_label.text = "Current throttle: \(throttle_decoded)"
//            }
            DispatchQueue.main.async {
                self.throt_return_label.text = "Current throttle: \(throttle_decoded)"
                self.velocity_label.text = "Current Velocity: \(velocity_decoded)"
            }
        }
    }
    
    func sendBLENewName(peripheral: CBPeripheral, message: String){
        if newNameCharacteristic != nil {
            peripheral.writeValue(message.data(using: .utf8)!, for: newNameCharacteristic, type: .withoutResponse)
            //AppInfo.forget()
        }
    }
    
}
