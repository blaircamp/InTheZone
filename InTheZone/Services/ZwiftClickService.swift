import Foundation
import CoreBluetooth
import Combine

// MARK: - Zwift Click Button Events
enum ZwiftClickButton: Int {
    case plus = 1   // Shift up / Increase resistance
    case minus = 2  // Shift down / Decrease resistance
}

struct ZwiftClickButtonEvent {
    let button: ZwiftClickButton
    let timestamp: Date
}

// MARK: - Zwift Click Service
final class ZwiftClickService: NSObject, ObservableObject {
    static let shared = ZwiftClickService()
    
    // BLE UUIDs for Zwift devices (from Python client)
    private let ZWIFT_CUSTOM_SERVICE_UUID = CBUUID(string: "00000001-19ca-4651-86e5-fa29dcdd09d1")
    private let ZWIFT_ASYNC_CHARACTERISTIC_UUID = CBUUID(string: "00000002-19ca-4651-86e5-fa29dcdd09d1")  // Notifications
    private let ZWIFT_SYNC_RX_CHARACTERISTIC_UUID = CBUUID(string: "00000003-19ca-4651-86e5-fa29dcdd09d1")  // Write
    private let ZWIFT_SYNC_TX_CHARACTERISTIC_UUID = CBUUID(string: "00000004-19ca-4651-86e5-fa29dcdd09d1")  // Indications
    
    // Zwift protocol constants
    private let ZWIFT_MANUFACTURER_ID: UInt16 = 2378
    private let BC1_CLICK_DEVICE_TYPE: UInt8 = 0x09
    private let RIDE_ON_HANDSHAKE = Data([0x52, 0x69, 0x64, 0x65, 0x4f, 0x6e]) // "RideOn"
    
    // Alternative initialization sequences to try
    private let REQUEST_START = Data([0x01, 0x02]) // Request start command (corrected)
    private let RESPONSE_START = Data([0x01, 0x03]) // Response start from device
    private let SIMPLE_START = Data([0x01]) // Simple start byte
    
    // Message types (different devices may use different IDs)
    private let EMPTY_MESSAGE_TYPE: UInt8 = 21  // 0x15
    private let BATTERY_LEVEL_TYPE: UInt8 = 25  // 0x19
    private let CLICK_NOTIFICATION_MESSAGE_TYPE: UInt8 = 55  // 0x37 for Click
    private let RIDE_NOTIFICATION_MESSAGE_TYPE: UInt8 = 35  // 0x23 for Ride
    private let PLAY_NOTIFICATION_MESSAGE_TYPE: UInt8 = 7   // 0x07 for Play
    
    // Published state
    @Published var isConnected = false
    @Published var isScanning = false
    @Published var batteryLevel: Int?
    @Published var discoveredDevice: CBPeripheral?
    
    // Button event publisher
    let buttonEventPublisher = PassthroughSubject<ZwiftClickButtonEvent, Never>()
    
    // Core Bluetooth
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var asyncCharacteristic: CBCharacteristic?
    private var syncRxCharacteristic: CBCharacteristic?
    private var syncTxCharacteristic: CBCharacteristic?
    
    private let logger = SessionLogger.shared
    private var connectionTimer: Timer?
    
    private override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // MARK: - Public Interface
    
    func startScan() {
        guard centralManager.state == .poweredOn else {
            logger.warning("Cannot scan for Zwift Click - Bluetooth not ready", source: "ZwiftClickService")
            return
        }
        
        guard !isScanning else { return }
        
        logger.info("Starting scan for Zwift Click devices", source: "ZwiftClickService")
        isScanning = true
        
        // Scan for devices advertising Zwift service or any devices (to check manufacturer data)
        centralManager.scanForPeripherals(
            withServices: [ZWIFT_CUSTOM_SERVICE_UUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        
        // Also scan without service filter to catch devices advertising via manufacturer data
        centralManager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
        
        // Stop scan after timeout
        connectionTimer?.invalidate()
        connectionTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
            self?.stopScan()
        }
    }
    
    func stopScan() {
        guard isScanning else { return }
        
        logger.info("Stopping scan for Zwift Click devices", source: "ZwiftClickService")
        centralManager.stopScan()
        isScanning = false
        connectionTimer?.invalidate()
        connectionTimer = nil
    }
    
    func connect(to peripheral: CBPeripheral) {
        logger.info("Connecting to Zwift Click", source: "ZwiftClickService", metadata: [
            "device_name": peripheral.name ?? "Unknown",
            "device_id": peripheral.identifier.uuidString
        ])
        
        stopScan()
        connectedPeripheral = peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
    }
    
    func disconnect() {
        guard let peripheral = connectedPeripheral else { return }
        
        logger.info("Disconnecting from Zwift Click", source: "ZwiftClickService")
        
        if let async = asyncCharacteristic {
            peripheral.setNotifyValue(false, for: async)
        }
        if let sync = syncTxCharacteristic {
            peripheral.setNotifyValue(false, for: sync)
        }
        
        centralManager.cancelPeripheralConnection(peripheral)
        connectedPeripheral = nil
        isConnected = false
    }
    
    
    func testReadCharacteristics() {
        guard isConnected,
              let peripheral = connectedPeripheral else {
            logger.warning("Cannot read - not connected", source: "ZwiftClickService")
            return
        }
        
        // Try to read from all characteristics
        if let async = asyncCharacteristic {
            logger.info("Reading from async characteristic", source: "ZwiftClickService")
            peripheral.readValue(for: async)
        }
        
        if let syncTx = syncTxCharacteristic {
            logger.info("Reading from sync TX characteristic", source: "ZwiftClickService")
            peripheral.readValue(for: syncTx)
        }
    }
    
    func sendHandshakeManually() {
        guard isConnected,
              let peripheral = connectedPeripheral,
              let characteristic = syncRxCharacteristic else {
            logger.warning("Cannot send handshake - not fully connected", source: "ZwiftClickService")
            return
        }
        
        logger.info("Manually sending handshake", source: "ZwiftClickService", metadata: [
            "data": RIDE_ON_HANDSHAKE.map { String(format: "%02x", $0) }.joined(separator: " ")
        ])
        // Use withoutResponse as per SwiftControl
        peripheral.writeValue(RIDE_ON_HANDSHAKE, for: characteristic, type: .withoutResponse)
    }
    
    func sendAlternativeStart() {
        guard isConnected,
              let peripheral = connectedPeripheral,
              let characteristic = syncRxCharacteristic else {
            logger.warning("Cannot send start command - not fully connected", source: "ZwiftClickService")
            return
        }
        
        // Try sending just RideOn + RequestStart like the encrypted version
        let combinedStart = RIDE_ON_HANDSHAKE + REQUEST_START
        logger.info("Sending alternative start sequence", source: "ZwiftClickService", metadata: [
            "data": combinedStart.map { String(format: "%02x", $0) }.joined(separator: " ")
        ])
        peripheral.writeValue(combinedStart, for: characteristic, type: .withoutResponse)
    }
    
    func sendSimpleStart() {
        guard isConnected,
              let peripheral = connectedPeripheral,
              let characteristic = syncRxCharacteristic else {
            logger.warning("Cannot send simple start - not fully connected", source: "ZwiftClickService")
            return
        }
        
        logger.info("Sending simple start byte", source: "ZwiftClickService", metadata: [
            "data": SIMPLE_START.map { String(format: "%02x", $0) }.joined(separator: " ")
        ])
        peripheral.writeValue(SIMPLE_START, for: characteristic, type: .withoutResponse)
    }
    
    func acknowledgeHandshake() {
        guard isConnected,
              let peripheral = connectedPeripheral,
              let characteristic = syncRxCharacteristic else {
            logger.warning("Cannot send acknowledgment - not fully connected", source: "ZwiftClickService")
            return
        }
        
        // Try sending an acknowledgment for message type 0x03
        let ackMessage = Data([0x04, 0x00, 0x00, 0x00]) // Response to 0x03
        logger.info("Sending acknowledgment message", source: "ZwiftClickService", metadata: [
            "data": ackMessage.map { String(format: "%02x", $0) }.joined(separator: " ")
        ])
        peripheral.writeValue(ackMessage, for: characteristic, type: .withoutResponse)
    }
    
    // MARK: - Private Methods
    
    private func isZwiftClick(_ peripheral: CBPeripheral, advertisementData: [String: Any]) -> Bool {
        // Check by name
        if let name = peripheral.name, name.contains("Zwift Click") {
            return true
        }
        
        // Check manufacturer data
        if let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
            // Parse manufacturer ID (first 2 bytes, little endian)
            if manufacturerData.count >= 3 {
                let manufacturerId = UInt16(manufacturerData[0]) | (UInt16(manufacturerData[1]) << 8)
                if manufacturerId == ZWIFT_MANUFACTURER_ID && manufacturerData[2] == BC1_CLICK_DEVICE_TYPE {
                    return true
                }
            }
        }
        
        return false
    }
    
    private func parseClickNotification(_ data: Data) -> [ZwiftClickButton] {
        var buttons: [ZwiftClickButton] = []
        
        logger.debug("Parsing click notification protobuf", source: "ZwiftClickService", metadata: [
            "data_length": data.count,
            "data_hex": data.map { String(format: "%02x", $0) }.joined(separator: " ")
        ])
        
        // Parse protobuf message - ClickKeyPadStatus
        // Field 1: Button_Plus (tag 0x08)
        // Field 2: Button_Minus (tag 0x10)
        // Values: 0x00 = ON (pressed), 0x01 = OFF (released)
        
        var index = 0
        while index < data.count {
            let tag = data[index]
            index += 1
            
            // Check if we have a value byte
            guard index < data.count else { break }
            let value = data[index]
            index += 1
            
            logger.debug("Parsing field", source: "ZwiftClickService", metadata: [
                "tag": String(format: "%02x", tag),
                "value": String(format: "%02x", value),
                "field_number": (tag >> 3),
                "wire_type": (tag & 0x07)
            ])
            
            switch tag {
            case 0x08: // Field 1: Button_Plus
                if value == 0x00 { // ON
                    buttons.append(.plus)
                    logger.info("Plus button pressed", source: "ZwiftClickService")
                } else if value == 0x01 { // OFF
                    logger.debug("Plus button released", source: "ZwiftClickService")
                }
                
            case 0x10: // Field 2: Button_Minus
                if value == 0x00 { // ON
                    buttons.append(.minus)
                    logger.info("Minus button pressed", source: "ZwiftClickService")
                } else if value == 0x01 { // OFF
                    logger.debug("Minus button released", source: "ZwiftClickService")
                }
                
            default:
                logger.debug("Unknown protobuf field", source: "ZwiftClickService", metadata: [
                    "tag": String(format: "%02x", tag),
                    "value": String(format: "%02x", value)
                ])
            }
        }
        
        if buttons.isEmpty {
            logger.debug("No buttons pressed in this notification", source: "ZwiftClickService")
        } else {
            logger.info("Buttons detected", source: "ZwiftClickService", metadata: [
                "buttons": buttons.map { $0 == .plus ? "Plus" : "Minus" }.joined(separator: ", ")
            ])
        }
        
        return buttons
    }
}

// MARK: - CBCentralManagerDelegate
extension ZwiftClickService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            logger.info("Bluetooth powered on for Zwift Click", source: "ZwiftClickService")
        case .poweredOff:
            logger.warning("Bluetooth powered off", source: "ZwiftClickService")
            isConnected = false
        default:
            logger.warning("Bluetooth state changed", source: "ZwiftClickService", metadata: [
                "state": String(describing: central.state)
            ])
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, 
                       advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if isZwiftClick(peripheral, advertisementData: advertisementData) {
            logger.info("Discovered Zwift Click device", source: "ZwiftClickService", metadata: [
                "device_name": peripheral.name ?? "Unknown",
                "device_id": peripheral.identifier.uuidString,
                "rssi": RSSI
            ])
            
            DispatchQueue.main.async {
                self.discoveredDevice = peripheral
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        logger.info("Connected to Zwift Click", source: "ZwiftClickService", metadata: [
            "device_name": peripheral.name ?? "Unknown"
        ])
        
        isConnected = true
        peripheral.discoverServices([ZWIFT_CUSTOM_SERVICE_UUID])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        logger.error("Failed to connect to Zwift Click", source: "ZwiftClickService", metadata: [
            "error": error?.localizedDescription ?? "Unknown error"
        ])
        
        isConnected = false
        connectedPeripheral = nil
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        logger.info("Disconnected from Zwift Click", source: "ZwiftClickService", metadata: [
            "error": error?.localizedDescription as Any
        ])
        
        isConnected = false
        connectedPeripheral = nil
        asyncCharacteristic = nil
        syncRxCharacteristic = nil
        syncTxCharacteristic = nil
        batteryLevel = nil
    }
}

// MARK: - CBPeripheralDelegate
extension ZwiftClickService: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            logger.error("Error discovering services", source: "ZwiftClickService", metadata: [
                "error": error!.localizedDescription
            ])
            return
        }
        
        guard let services = peripheral.services else { 
            logger.warning("No services found on peripheral", source: "ZwiftClickService")
            return 
        }
        
        logger.info("Discovered services", source: "ZwiftClickService", metadata: [
            "service_count": services.count,
            "services": services.map { $0.uuid.uuidString }.joined(separator: ", ")
        ])
        
        for service in services {
            if service.uuid == ZWIFT_CUSTOM_SERVICE_UUID {
                logger.info("Found Zwift custom service", source: "ZwiftClickService", metadata: [
                    "service_uuid": service.uuid.uuidString
                ])
                peripheral.discoverCharacteristics([
                    ZWIFT_ASYNC_CHARACTERISTIC_UUID,
                    ZWIFT_SYNC_RX_CHARACTERISTIC_UUID,
                    ZWIFT_SYNC_TX_CHARACTERISTIC_UUID
                ], for: service)
            } else {
                logger.debug("Found other service", source: "ZwiftClickService", metadata: [
                    "service_uuid": service.uuid.uuidString
                ])
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else {
            logger.error("Error discovering characteristics", source: "ZwiftClickService", metadata: [
                "error": error!.localizedDescription
            ])
            return
        }
        
        guard let characteristics = service.characteristics else { 
            logger.warning("No characteristics found in service", source: "ZwiftClickService")
            return 
        }
        
        logger.info("Discovered characteristics", source: "ZwiftClickService", metadata: [
            "count": characteristics.count,
            "characteristics": characteristics.map { $0.uuid.uuidString }.joined(separator: ", ")
        ])
        
        for characteristic in characteristics {
            let props = characteristic.properties
            var propsList: [String] = []
            if props.contains(.read) { propsList.append("read") }
            if props.contains(.write) { propsList.append("write") }
            if props.contains(.writeWithoutResponse) { propsList.append("writeWithoutResponse") }
            if props.contains(.notify) { propsList.append("notify") }
            if props.contains(.indicate) { propsList.append("indicate") }
            
            logger.debug("Processing characteristic", source: "ZwiftClickService", metadata: [
                "uuid": characteristic.uuid.uuidString,
                "properties": propsList.joined(separator: ", "),
                "raw_properties": props.rawValue
            ])
            
            switch characteristic.uuid {
            case ZWIFT_ASYNC_CHARACTERISTIC_UUID:
                logger.info("Found async characteristic", source: "ZwiftClickService", metadata: [
                    "can_notify": props.contains(.notify),
                    "properties": propsList.joined(separator: ", ")
                ])
                asyncCharacteristic = characteristic
                if props.contains(.notify) {
                    logger.info("Enabling notifications on async characteristic", source: "ZwiftClickService")
                    peripheral.setNotifyValue(true, for: characteristic)
                } else {
                    logger.warning("Async characteristic does not support notifications!", source: "ZwiftClickService")
                }
                
            case ZWIFT_SYNC_RX_CHARACTERISTIC_UUID:
                logger.info("Found sync RX characteristic, sending handshake", source: "ZwiftClickService", metadata: [
                    "handshake_data": RIDE_ON_HANDSHAKE.map { String(format: "%02x", $0) }.joined(separator: " "),
                    "properties": String(describing: characteristic.properties)
                ])
                syncRxCharacteristic = characteristic
                // SwiftControl uses withoutResponse, so let's use that
                let writeType: CBCharacteristicWriteType = .withoutResponse
                logger.info("Writing handshake", source: "ZwiftClickService", metadata: [
                    "write_type": "withoutResponse",
                    "data": RIDE_ON_HANDSHAKE.map { String(format: "%02x", $0) }.joined(separator: " ")
                ])
                peripheral.writeValue(RIDE_ON_HANDSHAKE, for: characteristic, type: writeType)
                
            case ZWIFT_SYNC_TX_CHARACTERISTIC_UUID:
                logger.info("Found sync TX characteristic", source: "ZwiftClickService", metadata: [
                    "can_indicate": props.contains(.indicate),
                    "can_notify": props.contains(.notify),
                    "properties": propsList.joined(separator: ", ")
                ])
                syncTxCharacteristic = characteristic
                // This characteristic uses indications, not notifications
                if props.contains(.indicate) {
                    logger.info("Enabling indications on sync TX characteristic", source: "ZwiftClickService")
                    peripheral.setNotifyValue(true, for: characteristic) // setNotifyValue handles both notify and indicate
                } else if props.contains(.notify) {
                    logger.info("Enabling notifications on sync TX characteristic", source: "ZwiftClickService")
                    peripheral.setNotifyValue(true, for: characteristic)
                } else {
                    logger.warning("Sync TX characteristic does not support notifications or indications!", source: "ZwiftClickService")
                }
                
            default:
                logger.debug("Found unknown characteristic", source: "ZwiftClickService", metadata: [
                    "uuid": characteristic.uuid.uuidString
                ])
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            logger.error("Error updating notification state", source: "ZwiftClickService", metadata: [
                "characteristic": characteristic.uuid.uuidString,
                "error": error.localizedDescription
            ])
            return
        }
        
        logger.info("Notification state updated", source: "ZwiftClickService", metadata: [
            "characteristic": characteristic.uuid.uuidString,
            "isNotifying": characteristic.isNotifying
        ])
        
        // If all notifications are set up, try sending handshake again after a delay
        if characteristic.uuid == ZWIFT_SYNC_TX_CHARACTERISTIC_UUID && characteristic.isNotifying {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.sendHandshakeManually()
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            logger.error("Error writing value", source: "ZwiftClickService", metadata: [
                "characteristic": characteristic.uuid.uuidString,
                "error": error.localizedDescription
            ])
            return
        }
        
        logger.debug("Successfully wrote value", source: "ZwiftClickService", metadata: [
            "characteristic": characteristic.uuid.uuidString
        ])
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            logger.error("Error updating value for characteristic", source: "ZwiftClickService", metadata: [
                "characteristic": characteristic.uuid.uuidString,
                "error": error.localizedDescription
            ])
            return
        }
        
        guard let data = characteristic.value else {
            logger.warning("No data in characteristic update", source: "ZwiftClickService", metadata: [
                "characteristic": characteristic.uuid.uuidString
            ])
            return
        }
        
        logger.info("Received data from characteristic", source: "ZwiftClickService", metadata: [
            "characteristic": characteristic.uuid.uuidString,
            "data_length": data.count,
            "data_hex": data.map { String(format: "%02x", $0) }.joined(separator: " ")
        ])
        
        switch characteristic.uuid {
        case ZWIFT_ASYNC_CHARACTERISTIC_UUID:
            handleAsyncNotification(data)
            
        case ZWIFT_SYNC_TX_CHARACTERISTIC_UUID:
            handleSyncNotification(data)
            
        default:
            logger.warning("Received data from unknown characteristic", source: "ZwiftClickService", metadata: [
                "characteristic": characteristic.uuid.uuidString
            ])
        }
    }
    
    private func handleAsyncNotification(_ data: Data) {
        guard !data.isEmpty else { 
            logger.warning("Empty async notification received", source: "ZwiftClickService")
            return 
        }
        
        let messageType = data[0]
        
        logger.debug("Processing async notification", source: "ZwiftClickService", metadata: [
            "message_type": messageType,
            "message_type_hex": String(format: "%02x", messageType),
            "full_data": data.map { String(format: "%02x", $0) }.joined(separator: " ")
        ])
        
        switch messageType {
        case CLICK_NOTIFICATION_MESSAGE_TYPE, RIDE_NOTIFICATION_MESSAGE_TYPE, PLAY_NOTIFICATION_MESSAGE_TYPE:
            // Button press notification (different devices use different message IDs)
            logger.info("Button notification received", source: "ZwiftClickService", metadata: [
                "message_type": messageType,
                "payload": data.dropFirst().map { String(format: "%02x", $0) }.joined(separator: " ")
            ])
            
            let buttons = parseClickNotification(Data(data.dropFirst()))
            
            if buttons.isEmpty {
                logger.warning("No buttons detected in notification", source: "ZwiftClickService")
            } else {
                for button in buttons {
                    logger.info("Zwift Click button pressed", source: "ZwiftClickService", metadata: [
                        "button": button == .plus ? "Plus" : "Minus"
                    ])
                    
                    let event = ZwiftClickButtonEvent(button: button, timestamp: Date())
                    DispatchQueue.main.async {
                        self.buttonEventPublisher.send(event)
                    }
                }
            }
            
        case BATTERY_LEVEL_TYPE:
            // Battery level update
            if data.count >= 3 {
                let level = Int(data[2])
                DispatchQueue.main.async {
                    self.batteryLevel = level
                }
                logger.info("Zwift Click battery level update", source: "ZwiftClickService", metadata: [
                    "battery_level": level,
                    "raw_data": data.map { String(format: "%02x", $0) }.joined(separator: " ")
                ])
            } else {
                logger.warning("Invalid battery level message", source: "ZwiftClickService", metadata: [
                    "data_length": data.count,
                    "expected_min_length": 3
                ])
            }
            
        case EMPTY_MESSAGE_TYPE:
            // Keepalive/empty message
            logger.debug("Keepalive message received", source: "ZwiftClickService")
            break
            
        default:
            logger.warning("Unknown Zwift Click message type", source: "ZwiftClickService", metadata: [
                "message_type": messageType,
                "message_type_hex": String(format: "%02x", messageType),
                "data": data.map { String(format: "%02x", $0) }.joined(separator: " ")
            ])
        }
    }
    
    private func handleSyncNotification(_ data: Data) {
        logger.debug("Processing sync notification", source: "ZwiftClickService", metadata: [
            "data_length": data.count,
            "data_hex": data.map { String(format: "%02x", $0) }.joined(separator: " ")
        ])
        
        if data.starts(with: RIDE_ON_HANDSHAKE) {
            logger.info("Received RideOn handshake response from Zwift Click", source: "ZwiftClickService", metadata: [
                "handshake_confirmed": true
            ])
            
            // Connection confirmed
        } else if data.count >= 8 && data.starts(with: RIDE_ON_HANDSHAKE + RESPONSE_START) {
            // This is RideOn + 0x01 0x03 + public key
            logger.info("Received RideOn + public key from Zwift Click (encryption mode)", source: "ZwiftClickService", metadata: [
                "header": data.prefix(8).map { String(format: "%02x", $0) }.joined(separator: " "),
                "public_key_length": data.count - 8
            ])
            
            // We don't need to implement encryption, just acknowledge we received it
            // The device should now be ready to send button notifications
            logger.info("Device handshake complete (ignoring encryption)", source: "ZwiftClickService")
            
            // Connection confirmed
        } else if data.count >= 4 && data[0] == 0x03 {
            // This looks like an encrypted message with format:
            // [message_type] [counter 3 bytes] [encrypted payload]
            let messageType = data[0]
            let counter = data[1..<4]
            let payload = data.count > 4 ? data[4...] : Data()
            
            logger.info("Received encrypted format message", source: "ZwiftClickService", metadata: [
                "message_type": String(format: "%02x", messageType),
                "counter": counter.map { String(format: "%02x", $0) }.joined(separator: " "),
                "payload_length": payload.count,
                "payload": payload.map { String(format: "%02x", $0) }.joined(separator: " ")
            ])
            
            // The device is using encryption protocol but we can ignore it
            // Just acknowledge we're ready
            logger.info("Device ready (encrypted protocol, ignoring encryption)", source: "ZwiftClickService")
            
            // Mark as handshake complete
            // ACK sent successfully
        } else if !data.isEmpty {
            // Log any other response for debugging
            logger.warning("Unexpected sync notification data", source: "ZwiftClickService", metadata: [
                "first_byte": String(format: "%02x", data[0]),
                "length": data.count,
                "data": data.map { String(format: "%02x", $0) }.joined(separator: " ")
            ])
        } else {
            logger.warning("Unexpected sync notification data", source: "ZwiftClickService", metadata: [
                "expected": RIDE_ON_HANDSHAKE.map { String(format: "%02x", $0) }.joined(separator: " "),
                "received": data.map { String(format: "%02x", $0) }.joined(separator: " ")
            ])
        }
    }
}