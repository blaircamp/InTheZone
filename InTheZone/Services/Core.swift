import Foundation
import CoreBluetooth
import Combine

// Connection status used by UI
enum ConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case bluetoothOff
    case unauthorized
    case unsupported
    case failed

    var displayText: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .bluetoothOff: return "Bluetooth Off"
        case .unauthorized: return "Unauthorized"
        case .unsupported: return "Unsupported"
        case .failed: return "Failed"
        }
    }

    var isTerminal: Bool {
        switch self { case .connected, .failed, .disconnected: return true; default: return false }
    }
}

// Simple HR validator
enum HeartRateValidator {
    static func isValid(_ hr: Double) -> Bool { hr > 20 && hr < 240 }
    static func formatHeartRate(_ hr: Double) -> String { String(Int(hr)) }
    static func shouldUseWatchHeartRate(source: HeartRateSource, trainerHeartRate: Int, watchHeartRate: Double) -> Bool {
        switch source {
        case .watch: return true
        case .trainer: return trainerHeartRate == 0
        case .auto: return trainerHeartRate == 0 && watchHeartRate > 0
        }
    }
}

// Core trainer snapshot
struct TrainerData: Identifiable {
    let id = UUID()
    var timestamp: Date = Date()
    var power: Int?
    var cadence: Double?
    var speed: Double?
    var resistance: Int?
    var heartRate: Int?
}

enum ResistanceChangeDirection { case increase, decrease }

struct ResistanceEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let direction: ResistanceChangeDirection
    let powerAtEvent: Int
}

enum FitnessLevel: String, CaseIterable, Codable { case beginner, intermediate, advanced, elite }

enum HeartRateSource: String, CaseIterable, Codable { case watch, trainer, auto }

enum ActiveHeartRateSource {
    case watch
    case trainer
    case none
}

struct UserProfile: Codable { var age = 35; var weight = 75.0; var fitnessLevel: FitnessLevel = .intermediate; var restingHR = 60; var maxHR: Int { 220 - age } }

// Training constants
enum TrainingConstants {
    // Access to SessionManager from non-view layer (lightweight proxy)
    // This avoids tight coupling; it should be set in app bootstrap.
    class SessionManagerProxy {
        static let shared = SessionManagerProxy()
        weak var manager: SessionManager?
        @MainActor
        func recordAutoResistanceChange(old: Int, new: Int) {
            manager?.recordResistanceChange(oldResistance: Double(old), newResistance: Double(new), reason: .pid)
        }
    }
    enum Communication { static let scanTimeout: TimeInterval = 8 }
    enum Resistance { 
        static let minimum = 0
        static let maximum = 100
        static let defaultStepSize = 1
        static let minStepSize = 1
        static let maxStepSize = 25
        static let stepSizeKey = "resistanceStepSize"
        static var stepSize: Int {
            let stored = UserDefaults.standard.integer(forKey: stepSizeKey)
            return stored > 0 ? min(max(stored, minStepSize), maxStepSize) : defaultStepSize
        }
    }
    enum Validation {
        static let maxSpeed: Double = 80
        static let maxCadence: Double = 220
        static let maxPower: Int = 2000
        static let speedSmoothingFactor = 0.3
        static let cadenceSmoothingFactor = 0.3
        static let powerSmoothingFactor = 0.3
    }
    enum History { static let maxDataPoints = 600; static let maxResistanceEvents = 200 }
    enum Session { static let statsUpdateInterval = 5 }
    enum HeartRateZones {
        static let lowerKey = "hrZoneLower"
        static let upperKey = "hrZoneUpper"
        static let defaultLower: Double = 130
        static let defaultUpper: Double = 150
        static var lower: Double { UserDefaults.standard.object(forKey: lowerKey) as? Double ?? defaultLower }
        static var upper: Double { UserDefaults.standard.object(forKey: upperKey) as? Double ?? defaultUpper }
        static func set(lower: Double, upper: Double) {
            UserDefaults.standard.set(lower, forKey: lowerKey)
            UserDefaults.standard.set(upper, forKey: upperKey)
        }
    }
}

// BluetoothCommunicationService (minimal stub; extend later if needed)
protocol BluetoothCommunicationServiceProtocol: AnyObject {
    var isBluetoothReady: Bool { get }
    var connectionStatus: ConnectionStatus { get }
    var discoveredPeripherals: [CBPeripheral] { get }
    var isScanning: Bool { get }
    func startScan()
    func stopScan()
    func connect(to peripheral: CBPeripheral)
    func disconnect()
    func sendControlCommand(opCode: UInt8, parameters: Data, completion: @escaping (Bool) -> Void)
    func readSupportedResistanceRange()
}

protocol BluetoothCommunicationDelegate: AnyObject {
    func bluetoothCommunicationDidConnect(_ peripheral: CBPeripheral)
    func bluetoothCommunicationDidFailToConnect(_ peripheral: CBPeripheral, error: Error?)
    func bluetoothCommunicationDidDisconnect(_ peripheral: CBPeripheral, error: Error?)
    func bluetoothCommunicationDidReceiveData(_ data: Data, for characteristic: CBCharacteristic)
}

final class BluetoothCommunicationService: NSObject, ObservableObject, BluetoothCommunicationServiceProtocol {
    @Published var isBluetoothReady = false
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var discoveredPeripherals: [CBPeripheral] = []
    @Published var isScanning = false

    private var centralManager: CBCentralManager!
    private var trainerPeripheral: CBPeripheral?
    private var controlPointCharacteristic: CBCharacteristic?
    private var supportedResistanceRangeCharacteristic: CBCharacteristic?

    private var lastCommandTime = Date()
    private let minCommandInterval: TimeInterval = 0.3

    weak var delegate: BluetoothCommunicationDelegate?

    private let ftmsServiceUUID = CBUUID(string: "00001826-0000-1000-8000-00805f9b34fb")
    private let heartRateServiceUUID = CBUUID(string: "0000180d-0000-1000-8000-00805f9b34fb")
    private let indoorBikeDataCharUUID = CBUUID(string: "00002ad2-0000-1000-8000-00805f9b34fb")
    private let heartRateMeasurementCharUUID = CBUUID(string: "00002a37-0000-1000-8000-00805f9b34fb")
    private let fitnessMachineControlPointCharUUID = CBUUID(string: "00002ad9-0000-1000-8000-00805f9b34fb")
    private let supportedResistanceRangeCharUUID = CBUUID(string: "00002ad6-0000-1000-8000-00805f9b34fb")

    // Expose UUIDs for external reference if needed
    var controlPointUUID: CBUUID { fitnessMachineControlPointCharUUID }
    var indoorBikeDataUUID: CBUUID { indoorBikeDataCharUUID }
    var resistanceRangeUUID: CBUUID { supportedResistanceRangeCharUUID }

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func startScan() {
        guard centralManager.state == .poweredOn else { return }
        discoveredPeripherals.removeAll()
        isScanning = true
        centralManager.scanForPeripherals(withServices: [ftmsServiceUUID], options: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + TrainingConstants.Communication.scanTimeout) { [weak self] in
            if self?.isScanning == true { self?.stopScan() }
        }
    }

    func stopScan() {
        centralManager.stopScan(); isScanning = false
    }

    func connect(to peripheral: CBPeripheral) {
        stopScan(); trainerPeripheral = peripheral; connectionStatus = .connecting
        centralManager.connect(peripheral, options: nil)
    }

    func disconnect() {
        guard let p = trainerPeripheral else { return }
        centralManager.cancelPeripheralConnection(p)
        trainerPeripheral = nil; controlPointCharacteristic = nil; supportedResistanceRangeCharacteristic = nil
        connectionStatus = .disconnected
    }

    func sendControlCommand(opCode: UInt8, parameters: Data = Data(), completion: @escaping (Bool) -> Void) {
        guard let p = trainerPeripheral, let ch = controlPointCharacteristic, p.state == .connected else { 
            print("❌ Cannot send control command - missing prerequisites")
            print("   Peripheral: \(trainerPeripheral?.name ?? "nil")")
            print("   Control Point: \(controlPointCharacteristic?.uuid.uuidString ?? "nil")")
            print("   Connected: \(trainerPeripheral?.state == .connected)")
            completion(false)
            return 
        }
        
        let now = Date(); let dt = now.timeIntervalSince(lastCommandTime)
        if dt < minCommandInterval { 
            print("⏱️ Command throttled, retrying in \(minCommandInterval - dt)s")
            DispatchQueue.main.asyncAfter(deadline: .now() + (minCommandInterval - dt)) { 
                self.sendControlCommand(opCode: opCode, parameters: parameters, completion: completion) 
            }
            return 
        }
        
        var data = Data(); data.append(opCode); data.append(parameters)
        let dataHex = data.map { String(format: "%02x", $0) }.joined(separator: " ")
        let commandName = opCode == 0x00 ? "Request Control" :
                         opCode == 0x04 ? "Set Resistance" :
                         opCode == 0x07 ? "Start/Resume" :
                         opCode == 0x08 ? "Stop/Pause" : "Unknown"
        
        print("📤 Sending \(commandName) command: \(dataHex)")
        p.writeValue(data, for: ch, type: .withResponse)
        lastCommandTime = now
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { 
            print("✅ Command sent (timeout-based success)")
            completion(true) 
        }
    }

    func readSupportedResistanceRange() {
        guard let p = trainerPeripheral, let ch = supportedResistanceRangeCharacteristic, p.state == .connected else { return }
        p.readValue(for: ch)
    }
}

extension BluetoothCommunicationService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: isBluetoothReady = true
        case .poweredOff: isBluetoothReady = false; connectionStatus = .bluetoothOff
        case .unauthorized: isBluetoothReady = false; connectionStatus = .unauthorized
        case .unsupported: isBluetoothReady = false; connectionStatus = .unsupported
        default: isBluetoothReady = false; connectionStatus = .disconnected
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if !discoveredPeripherals.contains(where: { $0.identifier == peripheral.identifier }) { discoveredPeripherals.append(peripheral) }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionStatus = .connected; peripheral.delegate = self
        print("🔗 Connected to trainer: \(peripheral.name ?? "Unknown")")
        print("🔍 Starting service discovery...")
        peripheral.discoverServices([ftmsServiceUUID, heartRateServiceUUID])
        delegate?.bluetoothCommunicationDidConnect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionStatus = .failed; delegate?.bluetoothCommunicationDidFailToConnect(peripheral, error: error)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectionStatus = .disconnected; trainerPeripheral = nil; controlPointCharacteristic = nil; supportedResistanceRangeCharacteristic = nil
        delegate?.bluetoothCommunicationDidDisconnect(peripheral, error: error)
    }
}

extension BluetoothCommunicationService: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("❌ Service discovery failed: \(error.localizedDescription)")
            return
        }
        
        guard let services = peripheral.services else { 
            print("❌ No services found")
            return 
        }
        
        print("✅ Found \(services.count) service(s):")
        for service in services {
            let serviceName = service.uuid == ftmsServiceUUID ? "FTMS" : 
                            service.uuid == heartRateServiceUUID ? "Heart Rate" : "Other"
            print("   📡 \(serviceName) Service: \(service.uuid)")
            
            let chars = [indoorBikeDataCharUUID, fitnessMachineControlPointCharUUID, heartRateMeasurementCharUUID, supportedResistanceRangeCharUUID]
            print("   🔍 Discovering characteristics...")
            peripheral.discoverCharacteristics(chars, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("❌ Characteristic discovery failed for service \(service.uuid): \(error.localizedDescription)")
            return
        }
        
        guard let characteristics = service.characteristics else { 
            print("❌ No characteristics found for service \(service.uuid)")
            return 
        }
        
        let serviceName = service.uuid == ftmsServiceUUID ? "FTMS" : 
                        service.uuid == heartRateServiceUUID ? "Heart Rate" : "Other"
        print("✅ Found \(characteristics.count) characteristic(s) in \(serviceName) service:")
        
        for c in characteristics {
            let charName: String
            switch c.uuid {
            case fitnessMachineControlPointCharUUID:
                charName = "Fitness Machine Control Point"
                controlPointCharacteristic = c
                print("   🎮 \(charName): \(c.uuid)")
                print("   🔔 Enabling indications...")
                peripheral.setNotifyValue(true, for: c)
            case supportedResistanceRangeCharUUID:
                charName = "Supported Resistance Range"
                supportedResistanceRangeCharacteristic = c
                print("   📊 \(charName): \(c.uuid)")
                print("   📖 Reading resistance range...")
                readSupportedResistanceRange()
            case indoorBikeDataCharUUID:
                charName = "Indoor Bike Data"
                print("   🚴 \(charName): \(c.uuid)")
                print("   🔔 Enabling notifications...")
                peripheral.setNotifyValue(true, for: c)
            case heartRateMeasurementCharUUID:
                charName = "Heart Rate Measurement"
                print("   ❤️ \(charName): \(c.uuid)")
                print("   🔔 Enabling notifications...")
                peripheral.setNotifyValue(true, for: c)
            default: 
                charName = "Other"
                print("   ❓ \(charName): \(c.uuid)")
                break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("❌ Data update failed for \(characteristic.uuid): \(error.localizedDescription)")
            return
        }
        
        guard let data = characteristic.value else {
            print("❌ No data received for \(characteristic.uuid)")
            return
        }
        
        let charName: String
        switch characteristic.uuid {
        case indoorBikeDataCharUUID: charName = "Indoor Bike Data"
        case heartRateMeasurementCharUUID: charName = "Heart Rate"
        case supportedResistanceRangeCharUUID: charName = "Resistance Range"
        case fitnessMachineControlPointCharUUID: charName = "Control Point Response"
        default: charName = "Unknown"
        }
        
        let dataHex = data.map { String(format: "%02x", $0) }.joined(separator: " ")
        print("📦 Received \(charName) data (\(data.count) bytes): \(dataHex)")
        
        delegate?.bluetoothCommunicationDidReceiveData(data, for: characteristic)
    }
}

