import Foundation
import CoreBluetooth
import Combine

// High-level facade coordinating communication, data, sessions, and watch HR.
final class BluetoothService: NSObject, ObservableObject {
    static let shared = BluetoothService()

    // Published UI state
    @Published var discoveredPeripherals: [CBPeripheral] = []
    @Published var isScanning = false
    @Published var trainerConnectionStatus: ConnectionStatus = .disconnected
    @Published var trainerData: TrainerData = TrainerData()
    @Published var isBluetoothReady = false
    @Published var isSessionActive = false
    @Published var powerHistory: [TrainerData] = []
    @Published var resistanceEvents: [ResistanceEvent] = []
    @Published var resistanceRange: (min: Int, max: Int, increment: Int)? = nil
    private var observedResistanceValues: Set<Int> = []
    private var hasSetDynamicRange = false
    @Published var resistanceStateManager = ResistanceStateManager() // Centralized resistance state
    
    // Zwift Click integration
    @Published var zwiftClickConnected = false
    private let zwiftClickService = ZwiftClickService.shared
    private var zwiftClickCancellable: AnyCancellable?
    
    private let logger = SessionLogger.shared

    // Settings
    @Published var heartRateSource: HeartRateSource = {
        if let saved = UserDefaults.standard.string(forKey: "heartRateSource"), let src = HeartRateSource(rawValue: saved) { return src }
        return .auto
    }() {
        didSet {
            UserDefaults.standard.set(heartRateSource.rawValue, forKey: "heartRateSource")
        }
    }

    // Services
    private let communicationService = BluetoothCommunicationService()
    private let sessionManager = TrainerSessionManager()
    private let watchManager = WatchCommunicationManager()

    // Minimal data smoothing/validation state
    private var cancellables = Set<AnyCancellable>()
    private var lastValidSpeed: Double = 0
    private var currentResistanceLevel: Int = 0
    private var lastValidCadence: Double = 0
    private var lastValidPower: Int = 0

    // Control point feedback for UI
    @Published var lastControlPointMessage: String? = nil
    @Published var systemErrorMessage: String? = nil
    @Published var showSystemError: Bool = false

    private override init() {
        super.init()
        setupBindings()
        setupZwiftClickBindings()
    }

    // MARK: - Bindings
    private func setupBindings() {
        communicationService.$isBluetoothReady.assign(to: &self.$isBluetoothReady)
        communicationService.$connectionStatus.assign(to: &self.$trainerConnectionStatus)
        communicationService.$discoveredPeripherals.assign(to: &self.$discoveredPeripherals)
        communicationService.$isScanning.assign(to: &self.$isScanning)
        communicationService.delegate = self

        sessionManager.$sessionState.sink { [weak self] state in
            guard let self else { return }
            self.isSessionActive = (state == .active)
        }.store(in: &cancellables)

        // Subscribe to watch heart rate stream
        watchManager.heartRatePublisher.sink { [weak self] hr in
            guard let self else { return }
            let useWatch = self.heartRateSource == .watch || (self.heartRateSource == .auto && (self.trainerData.heartRate ?? 0) == 0)
            if useWatch, HeartRateValidator.isValid(hr) {
                // Always update display for live viewing
                self.trainerData.heartRate = Int(hr)
                
                // Only process for recording if session is active
                guard self.isSessionActive else { return }
                
                self.trainerData.timestamp = Date()
                self.sessionManager.recordDataPoint(self.trainerData)
            }
        }.store(in: &cancellables)
        
        // Subscribe to watch session commands
        watchManager.sessionCommandPublisher.sink { [weak self] command in
            guard let self else { return }
            guard self.isBluetoothReady && self.trainerConnectionStatus == .connected else {
                self.logger.warning("Watch requested session \(command) but trainer not connected", source: "BluetoothService")
                return
            }
            
            switch command {
            case "start":
                if !self.isSessionActive {
                    self.logger.info("Starting session from Watch command", source: "BluetoothService")
                    self.startSession()
                    // Also notify SessionManager to start tracking
                    Task { @MainActor in
                        TrainingConstants.SessionManagerProxy.shared.manager?.startSession()
                    }
                }
            case "stop":
                if self.isSessionActive {
                    self.logger.info("Stopping session from Watch command", source: "BluetoothService")
                    self.stopSession()
                    // Also notify SessionManager to stop tracking
                    Task { @MainActor in
                        TrainingConstants.SessionManagerProxy.shared.manager?.endSession()
                    }
                }
            default:
                self.logger.warning("Unknown session command from Watch: \(command)", source: "BluetoothService")
            }
        }.store(in: &cancellables)
    }
    
    // MARK: - Zwift Click Integration
    private func setupZwiftClickBindings() {
        // Monitor Zwift Click connection status
        zwiftClickService.$isConnected
            .assign(to: &$zwiftClickConnected)
        
        // Handle button events from Zwift Click
        zwiftClickCancellable = zwiftClickService.buttonEventPublisher
            .sink { [weak self] event in
                guard let self else { return }
                
                self.logger.info("Zwift Click button event received", source: "BluetoothService", metadata: [
                    "button": event.button == .plus ? "Plus" : "Minus"
                ])
                
                // Only process if trainer is connected
                guard self.trainerConnectionStatus == .connected else {
                    self.logger.warning("Zwift Click pressed but trainer not connected", source: "BluetoothService")
                    return
                }
                
                // Apply resistance change based on button
                let stepDirection = event.button == .plus ? 1 : -1
                self.adjustResistanceBySteps(stepDirection)
            }
    }
    
    func adjustResistanceBySteps(_ steps: Int) {
        // Use the step size from settings
        let stepSize = TrainingConstants.Resistance.stepSize
        let currentLevel = resistanceStateManager.displayLevel
        let adjustment = steps * stepSize
        let newLevel = currentLevel + adjustment
        
        // Use actual trainer resistance range if available
        let minRes = resistanceRange?.min ?? TrainingConstants.Resistance.minimum
        let maxRes = resistanceRange?.max ?? TrainingConstants.Resistance.maximum
        
        // Clamp to valid range
        let clamped = max(minRes, min(maxRes, newLevel))
        
        logger.debug("Adjusting resistance by steps", source: "BluetoothService", metadata: [
            "steps": steps,
            "step_size": stepSize,
            "current_level": currentLevel,
            "new_level": clamped
        ])
        
        setResistance(clamped)
    }
    
    // Auto-scan for Zwift Click after trainer connection
    func autoConnectZwiftClick() {
        guard !zwiftClickService.isConnected else { return }
        
        logger.info("Auto-scanning for Zwift Click", source: "BluetoothService")
        zwiftClickService.startScan()
        
        // Auto-connect if found
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            if let device = self?.zwiftClickService.discoveredDevice {
                self?.logger.info("Auto-connecting to discovered Zwift Click", source: "BluetoothService")
                self?.zwiftClickService.connect(to: device)
            }
        }
    }

    // MARK: - Public control
    func startScan() { 
        logger.info("Starting Bluetooth scan", source: "BluetoothService")
        communicationService.startScan() 
    }
    func stopScan() { 
        logger.info("Stopping Bluetooth scan", source: "BluetoothService")
        communicationService.stopScan() 
    }
    func connect(to peripheral: CBPeripheral) { 
        logger.info("Connecting to peripheral", source: "BluetoothService", metadata: [
            "peripheral_name": peripheral.name ?? "Unknown",
            "peripheral_id": peripheral.identifier.uuidString
        ])
        communicationService.connect(to: peripheral) 
    }
    func disconnect() { 
        logger.info("Disconnecting from peripheral", source: "BluetoothService")
        communicationService.disconnect() 
    }

    func readResistanceRange() { communicationService.readSupportedResistanceRange() }

    func startSession() {
        guard isBluetoothReady else { 
            logger.warning("Attempted to start session but Bluetooth not ready", source: "BluetoothService")
            return 
        }
        logger.info("Starting trainer session", source: "BluetoothService")
        _ = sessionManager.startSession()
        // Clear previous chart data when starting a new session
        powerHistory.removeAll()
        requestTrainerControl()
    }
    func stopSession() {
        logger.info("Stopping trainer session", source: "BluetoothService")
        _ = sessionManager.stopSession()
        sendStopCommandToTrainer()
    }

    func setResistance(_ level: Int) {
        // Check if resistance state manager can accept new command
        guard resistanceStateManager.canAcceptNewCommand() else {
            logger.debug("Resistance command rejected (debounced)", source: "BluetoothService", metadata: [
                "requested_level": level
            ])
            return
        }
        
        // Use actual trainer resistance range if available, otherwise fall back to constants
        let minRes = resistanceRange?.min ?? TrainingConstants.Resistance.minimum
        let maxRes = resistanceRange?.max ?? TrainingConstants.Resistance.maximum
        let clamped = max(minRes, min(maxRes, level))
        
        // Request resistance change through state manager
        guard resistanceStateManager.requestResistanceChange(to: clamped) else {
            logger.debug("Resistance change request rejected by state manager", source: "BluetoothService", metadata: [
                "requested_level": level,
                "clamped_level": clamped
            ])
            return
        }
        
        logger.debug("Setting resistance", source: "BluetoothService", metadata: [
            "requested_level": level,
            "clamped_level": clamped,
            "trainer_range": resistanceRange as Any
        ])
        
        let oldLevel = currentResistanceLevel
        let cmd = Data([0x04 /* setTargetResistanceLevel */, UInt8(clamped & 0xFF)])
        communicationService.sendControlCommand(opCode: cmd.first ?? 0, parameters: cmd.dropFirst()) { success in
            self.logger.debug("Resistance command result", source: "BluetoothService", metadata: [
                "success": success,
                "level": clamped
            ])
            
            // Send resistance change to Watch app if successful
            if success {
                self.currentResistanceLevel = clamped
                self.watchManager.sendResistanceChange(oldLevel: oldLevel, newLevel: clamped)
            }
        }
    }

    // MARK: - Command helpers
    private func requestTrainerControl() {
        logger.info("Requesting trainer control", source: "BluetoothService")
        let data = Data([0x00]) // request control
        communicationService.sendControlCommand(opCode: data.first ?? 0, parameters: data.dropFirst()) { [weak self] ok in
            if ok {
                self?.logger.info("Trainer control granted, sending start command", source: "BluetoothService")
                self?.sendStartCommandToTrainer()
            } else {
                self?.logger.error("Failed to gain trainer control", source: "BluetoothService")
            }
        }
    }
    private func sendStartCommandToTrainer() {
        logger.info("Sending start command to trainer", source: "BluetoothService")
        let data = Data([0x07])
        communicationService.sendControlCommand(opCode: data.first ?? 0, parameters: data.dropFirst()) { [weak self] ok in
            if ok {
                self?.logger.info("Start command sent successfully", source: "BluetoothService")
            } else {
                self?.logger.error("Failed to send start command", source: "BluetoothService")
            }
        }
    }
    private func sendStopCommandToTrainer() {
        logger.info("Sending stop command to trainer", source: "BluetoothService")
        // Some trainers require a parameter: 0x01 = stop, 0x02 = pause
        let data = Data([0x08, 0x01]) // Stop command with stop parameter
        communicationService.sendControlCommand(opCode: data.first ?? 0, parameters: data.dropFirst()) { [weak self] ok in
            if ok {
                self?.logger.info("Stop command sent successfully", source: "BluetoothService")
            } else {
                self?.logger.error("Failed to send stop command", source: "BluetoothService")
            }
        }
    }
}

extension BluetoothService: BluetoothCommunicationDelegate {
    func bluetoothCommunicationDidConnect(_ peripheral: CBPeripheral) {
        logger.info("Successfully connected to peripheral", source: "BluetoothService", metadata: [
            "peripheral_name": peripheral.name ?? "Unknown",
            "peripheral_id": peripheral.identifier.uuidString
        ])
        
        // Reset resistance state on new connection
        DispatchQueue.main.async {
            self.resistanceStateManager.reset()
            self.observedResistanceValues.removeAll()
            self.hasSetDynamicRange = false
            self.resistanceRange = nil
        }
        
        // Wait a bit for service/characteristic discovery to complete, then verify capabilities
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.verifyTrainerCapabilities()
            // Auto-connect to Zwift Click if available
            self.autoConnectZwiftClick()
        }
    }
    
    private func verifyTrainerCapabilities() {
        var capabilities: [String] = []
        var missingCapabilities: [String] = []
        
        // Check if we can read resistance range
        if resistanceRange != nil {
            capabilities.append("✅ Resistance Range Available")
        } else {
            missingCapabilities.append("❌ Resistance Range Not Available")
        }
        
        // Check connection status
        if trainerConnectionStatus == .connected {
            capabilities.append("✅ Connected to Trainer")
        } else {
            missingCapabilities.append("❌ Not Connected")
        }
        
        // The detailed characteristic verification will be shown in the console logs
        logger.debug("Detailed verification in console logs", source: "BluetoothService")
        
        logger.info("Trainer capabilities verified", source: "BluetoothService", metadata: [
            "capabilities": capabilities.joined(separator: ", "),
            "missing": missingCapabilities.joined(separator: ", "),
            "fully_functional": missingCapabilities.isEmpty
        ])
        
        if !missingCapabilities.isEmpty {
            logger.warning("Trainer missing some capabilities", source: "BluetoothService", metadata: [
                "missing_capabilities": missingCapabilities
            ])
        }
    }
    func bluetoothCommunicationDidFailToConnect(_ peripheral: CBPeripheral, error: Error?) {
        logger.error("Failed to connect to peripheral", source: "BluetoothService", metadata: [
            "peripheral_name": peripheral.name ?? "Unknown",
            "peripheral_id": peripheral.identifier.uuidString,
            "error": error?.localizedDescription ?? "Unknown error"
        ])
    }
    func bluetoothCommunicationDidDisconnect(_ peripheral: CBPeripheral, error: Error?) { 
        logger.info("Disconnected from peripheral", source: "BluetoothService", metadata: [
            "peripheral_name": peripheral.name ?? "Unknown",
            "peripheral_id": peripheral.identifier.uuidString,
            "error": error?.localizedDescription as Any
        ])
        
        // Reset resistance state on disconnection
        DispatchQueue.main.async {
            self.resistanceStateManager.reset()
            self.observedResistanceValues.removeAll()
            self.hasSetDynamicRange = false
            self.resistanceRange = nil
        }
        
        sessionManager.resetSession() 
    }
    func bluetoothCommunicationDidReceiveData(_ data: Data, for characteristic: CBCharacteristic) {
        let uuid = characteristic.uuid.uuidString.lowercased()
        logger.debug("Received Bluetooth data", source: "BluetoothService", metadata: [
            "characteristic_uuid": uuid,
            "data_length": data.count,
            "data_hex": data.map { String(format: "%02x", $0) }.joined(separator: " ")
        ])
        
        // Debug: Log exactly what UUID we're getting for Indoor Bike Data
        if uuid.contains("2ad2") {
            logger.info("Indoor Bike Data UUID detected", source: "BluetoothService", metadata: [
                "full_uuid": uuid,
                "attempting_parse": true
            ])
        }
        
        switch true {
        case uuid.contains("2a37"): // Heart Rate Measurement
            guard data.count >= 2 else { return }
            let flags = data[0]
            let is16Bit = (flags & 0x01) != 0
            let hr: Int
            if is16Bit {
                guard data.count >= 3 else { return }
                hr = Int(UInt16(data[1]) | (UInt16(data[2]) << 8))
            } else {
                hr = Int(data[1])
            }
            if HeartRateValidator.isValid(Double(hr)) {
                // Always update display for live viewing
                trainerData.heartRate = hr
                
                // Only process for recording and control if session is active
                guard isSessionActive else { return }
                
                let now = Date()
                trainerData.timestamp = now
                sessionManager.recordDataPoint(trainerData)
                
                logger.debug("Heart rate data processed", source: "BluetoothService", metadata: [
                    "raw_hr": hr
                ])
            } else {
                logger.warning("Invalid heart rate data received", source: "BluetoothService", metadata: [
                    "heart_rate": hr
                ])
            }
        case uuid.contains("2ad2"): // Indoor Bike Data
            logger.info("Processing Indoor Bike Data", source: "BluetoothService", metadata: [
                "data_hex": data.map { String(format: "%02x", $0) }.joined(separator: " "),
                "data_length": data.count,
                "session_active": isSessionActive
            ])
            
            let parser = FTMSDataParser()
            let sample = parser.parseIndoorBikeData(data)
            
            if let sample = sample {
                // Log all parsed data for debugging
                logger.info("Indoor bike data parsed successfully", source: "BluetoothService", metadata: [
                    "speed": sample.speed as Any,
                    "cadence": sample.cadence as Any,
                    "power": sample.power as Any,
                    "resistance": sample.resistance as Any,
                    "heart_rate": sample.heartRate as Any
                ])
                
                // Always update UI display metrics for live viewing (but don't process until session active)
                if let speed = sample.speed, speed >= 0 && speed <= TrainingConstants.Validation.maxSpeed {
                    trainerData.speed = speed
                }
                if let cadence = sample.cadence, cadence >= 0 && cadence <= TrainingConstants.Validation.maxCadence {
                    trainerData.cadence = cadence
                }
                if let power = sample.power, power >= 0 && power <= TrainingConstants.Validation.maxPower {
                    trainerData.power = power
                }
                // Also update heart rate display if from trainer
                if let hr = sample.heartRate, HeartRateValidator.isValid(Double(hr)) {
                    if heartRateSource == .trainer || (heartRateSource == .auto && (watchManager.lastHeartRate == 0)) {
                        trainerData.heartRate = hr
                    }
                }
                if let res = sample.resistance { 
                    trainerData.resistance = res
                    
                    // Track observed resistance values for dynamic range detection
                    observedResistanceValues.insert(res)
                    
                    // If trainer doesn't provide resistance range characteristic, infer it dynamically
                    if resistanceRange == nil && !hasSetDynamicRange && observedResistanceValues.count >= 8 {
                        // Once we've seen multiple values, try to determine the range
                        let minObserved = observedResistanceValues.min() ?? 0
                        let maxObserved = observedResistanceValues.max() ?? 100
                        
                        // Infer range with fallback safety
                        let inferredMin = max(0, minObserved) // Ensure non-negative
                        let inferredMax: Int
                        
                        // Determine max based on observed pattern with safety margins
                        if maxObserved <= 31 && observedResistanceValues.count >= 10 {
                            inferredMax = 31 // Confident it's 0-31 range
                        } else if maxObserved <= 20 && observedResistanceValues.count >= 8 {
                            inferredMax = 20 // Possible 0-20 range
                        } else if maxObserved > 50 {
                            inferredMax = 100 // Likely 0-100 range
                        } else {
                            // Fallback: extend observed max by 20% with reasonable bounds
                            inferredMax = min(100, max(31, Int(Double(maxObserved) * 1.2)))
                        }
                        
                        let inferredRange = (min: inferredMin, max: inferredMax, increment: 1)
                        
                        DispatchQueue.main.async {
                            self.resistanceRange = inferredRange
                            self.hasSetDynamicRange = true
                            self.logger.info("Dynamically detected resistance range", source: "BluetoothService", metadata: [
                                "min": inferredRange.min,
                                "max": inferredRange.max,
                                "increment": inferredRange.increment,
                                "observed_values": Array(self.observedResistanceValues).sorted()
                            ])
                        }
                    }
                    
                    // Update resistance state manager with level from trainer
                    DispatchQueue.main.async {
                        self.resistanceStateManager.updateResistanceLevel(res)
                    }
                }
                
                // Only process data for recording and analysis if session is active
                guard isSessionActive else { return }
                
                // Apply smoothing for session recording (overwrite the raw display values)
                if let speed = sample.speed, speed >= 0 && speed <= TrainingConstants.Validation.maxSpeed {
                    trainerData.speed = lastValidSpeed == 0 ? speed : (speed * TrainingConstants.Validation.speedSmoothingFactor + lastValidSpeed * (1 - TrainingConstants.Validation.speedSmoothingFactor))
                    lastValidSpeed = speed
                }
                if let cadence = sample.cadence, cadence >= 0 && cadence <= TrainingConstants.Validation.maxCadence {
                    trainerData.cadence = lastValidCadence == 0 ? cadence : (cadence * TrainingConstants.Validation.cadenceSmoothingFactor + lastValidCadence * (1 - TrainingConstants.Validation.cadenceSmoothingFactor))
                    lastValidCadence = cadence
                }
                if let power = sample.power, power >= 0 && power <= TrainingConstants.Validation.maxPower {
                    let smoothed = lastValidPower == 0 ? Double(power) : (Double(power) * TrainingConstants.Validation.powerSmoothingFactor + Double(lastValidPower) * (1 - TrainingConstants.Validation.powerSmoothingFactor))
                    let pInt = Int(smoothed.rounded())
                    trainerData.power = pInt
                    lastValidPower = power
                    appendPowerHistory(pInt)
                }
                // HR arbitration: prefer watch if source is watch/auto and trainer HR missing
                if let hr = sample.heartRate, HeartRateValidator.isValid(Double(hr)) {
                    if heartRateSource == .trainer || (heartRateSource == .auto && (watchManager.lastHeartRate == 0)) {
                        trainerData.heartRate = hr
                    }
                }
                trainerData.timestamp = sample.timestamp
                sessionManager.recordDataPoint(trainerData)
            } else {
                logger.warning("Failed to parse Indoor Bike Data", source: "BluetoothService", metadata: [
                    "data_hex": data.map { String(format: "%02x", $0) }.joined(separator: " "),
                    "data_length": data.count
                ])
            }
        case uuid.contains("2ad6"): // Supported Resistance Range
            let parser = FTMSDataParser()
            
            // Log raw data for debugging
            let rawBytes = data.map { String(format: "%02x", $0) }.joined(separator: " ")
            logger.info("Resistance range raw data", source: "BluetoothService", metadata: [
                "raw_bytes": rawBytes,
                "data_length": data.count
            ])
            
            if let range = parser.parseResistanceRange(data) {
                DispatchQueue.main.async { self.resistanceRange = range }
                logger.info("Parsed resistance range", source: "BluetoothService", metadata: [
                    "min": range.min,
                    "max": range.max,
                    "increment": range.increment
                ])
                print("FTMS resistance range: min=\(range.min) max=\(range.max) inc=\(range.increment)")
            } else {
                logger.warning("Failed to parse resistance range", source: "BluetoothService", metadata: [
                    "raw_bytes": rawBytes
                ])
            }
        case uuid.contains("2ad9"): // Control Point Response (indication)
            let cp = FTMSControlPointParser()
            if let resp = cp.parse(data) {
                let ok = (resp["success"] as? Bool) ?? false
                let msg = "\(resp["opcodeDescription"] as? String ?? "Command"): \(resp["resultDescription"] as? String ?? "")"
                DispatchQueue.main.async { 
                    self.lastControlPointMessage = msg 
                    
                    // Show user-facing error for failed commands
                    if !ok {
                        let errorMsg = "Trainer command failed: \(resp["resultDescription"] as? String ?? "Unknown error")"
                        self.systemErrorMessage = errorMsg
                        self.showSystemError = true
                        
                        // Auto-dismiss after 5 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                            if self.systemErrorMessage == errorMsg {
                                self.showSystemError = false
                            }
                        }
                    }
                }
                print("ControlPoint: \(resp)")
            }
        default:
            break
        }
    }
    private func appendPowerHistory(_ power: Int) {
        // Only add to history if session is active
        guard isSessionActive else { return }
        // Snapshot current metrics so the chart can show power, HR, and cadence together
        let point = TrainerData(
            timestamp: Date(),
            power: power,
            cadence: trainerData.cadence,
            speed: nil,
            resistance: nil,
            heartRate: trainerData.heartRate
        )
        powerHistory.append(point)
        if powerHistory.count > TrainingConstants.History.maxDataPoints { powerHistory.removeFirst() }
    }
}


