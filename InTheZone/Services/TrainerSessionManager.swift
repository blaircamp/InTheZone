import Foundation
import Combine

// MARK: - Session state and statistics
enum TrainerSessionState: String, CaseIterable { case inactive, starting, active, paused, stopping, completed, error }

struct TrainingSessionStats {
    var duration: TimeInterval = 0
    var averageHeartRate: Double = 0
    var maxHeartRate: Double = 0
    var averagePower: Double = 0
    var maxPower: Int = 0
    var totalEnergyExpended: Double = 0
    var averageSpeed: Double = 0
    var maxSpeed: Double = 0
    var averageCadence: Double = 0
    var maxCadence: Double = 0
    var dataPointsCollected: Int = 0

    var formattedDuration: String {
        let h = Int(duration) / 3600, m = (Int(duration) % 3600)/60, s = Int(duration)%60
        return h > 0 ? String(format: "%02d:%02d:%02d", h,m,s) : String(format: "%02d:%02d", m,s)
    }
}

protocol TrainerSessionManagerDelegate: AnyObject {
    func trainerSessionDidStart()
    func trainerSessionDidPause()
    func trainerSessionDidResume()
    func trainerSessionDidStop(_ stats: TrainingSessionStats)
    func trainerSessionDidReset()
    func trainerSessionDidRecordData(_ data: TrainerData)
    func trainerSessionDidUpdateDuration(_ duration: TimeInterval)
}

final class TrainerSessionManager: ObservableObject {
    @Published private(set) var sessionState: TrainerSessionState = .inactive
    @Published private(set) var sessionStats = TrainingSessionStats()
    @Published private(set) var sessionStartTime: Date?
    @Published private(set) var sessionDuration: TimeInterval = 0

    private var sessionTimer: Timer?
    private var pauseStartTime: Date?
    private var totalPausedTime: TimeInterval = 0

    private var collectedData: [TrainerData] = []
    private var heartRateReadings: [Double] = []
    private var powerReadings: [Int] = []
    private var speedReadings: [Double] = []
    private var cadenceReadings: [Double] = []
    
    private let logger = SessionLogger.shared

    weak var delegate: TrainerSessionManagerDelegate?

    func startSession() -> Result<Void, Error> {
        guard sessionState == .inactive || sessionState == .completed else { 
            logger.warning("Attempted to start session in invalid state", source: "TrainerSessionManager", metadata: [
                "current_state": sessionState.rawValue
            ])
            return .failure(NSError(domain:"session", code:1)) 
        }
        resetSessionData()
        sessionState = .starting
        sessionStartTime = Date()
        totalPausedTime = 0
        
        logger.info("Trainer session starting", source: "TrainerSessionManager", metadata: [
            "start_time": ISO8601DateFormatter().string(from: sessionStartTime!)
        ])
        
        startSessionTimer()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { 
            self.sessionState = .active
            self.logger.info("Trainer session activated", source: "TrainerSessionManager")
            self.delegate?.trainerSessionDidStart() 
        }
        return .success(())
    }

    func pauseSession() -> Result<Void, Error> {
        guard sessionState == .active else { 
            logger.warning("Attempted to pause session in invalid state", source: "TrainerSessionManager", metadata: [
                "current_state": sessionState.rawValue
            ])
            return .failure(NSError(domain:"session", code:2)) 
        }
        sessionState = .paused
        pauseStartTime = Date()
        sessionTimer?.invalidate()
        
        logger.info("Trainer session paused", source: "TrainerSessionManager", metadata: [
            "pause_time": ISO8601DateFormatter().string(from: pauseStartTime!),
            "duration_at_pause": sessionDuration
        ])
        
        delegate?.trainerSessionDidPause()
        return .success(())
    }

    func resumeSession() -> Result<Void, Error> {
        guard sessionState == .paused else { 
            logger.warning("Attempted to resume session in invalid state", source: "TrainerSessionManager", metadata: [
                "current_state": sessionState.rawValue
            ])
            return .failure(NSError(domain:"session", code:3)) 
        }
        if let pauseStart = pauseStartTime { 
            let pauseDuration = Date().timeIntervalSince(pauseStart)
            totalPausedTime += pauseDuration
            pauseStartTime = nil
            
            logger.info("Trainer session resumed", source: "TrainerSessionManager", metadata: [
                "pause_duration": pauseDuration,
                "total_paused_time": totalPausedTime
            ])
        }
        sessionState = .active
        startSessionTimer()
        delegate?.trainerSessionDidResume()
        return .success(())
    }

    func stopSession() -> Result<TrainingSessionStats, Error> {
        guard sessionState == .active || sessionState == .paused else { 
            logger.warning("Attempted to stop session in invalid state", source: "TrainerSessionManager", metadata: [
                "current_state": sessionState.rawValue
            ])
            return .failure(NSError(domain:"session", code:4)) 
        }
        sessionState = .stopping
        sessionTimer?.invalidate()
        calculateFinalStatistics()
        sessionState = .completed
        
        let stats = sessionStats
        logger.info("Trainer session stopped", source: "TrainerSessionManager", metadata: [
            "final_duration": stats.duration,
            "data_points": stats.dataPointsCollected,
            "avg_hr": stats.averageHeartRate,
            "max_hr": stats.maxHeartRate,
            "avg_power": stats.averagePower,
            "max_power": stats.maxPower
        ])
        
        delegate?.trainerSessionDidStop(stats)
        return .success(stats)
    }

    func recordDataPoint(_ data: TrainerData) {
        guard sessionState == .active else { 
            logger.debug("Attempted to record data point in inactive session", source: "TrainerSessionManager", metadata: [
                "current_state": sessionState.rawValue
            ])
            return 
        }
        
        collectedData.append(data)
        sessionStats.dataPointsCollected += 1
        
        if let hr = data.heartRate { 
            heartRateReadings.append(Double(hr))
            sessionStats.maxHeartRate = max(sessionStats.maxHeartRate, Double(hr))
        }
        if let p = data.power, p > 0 { 
            powerReadings.append(p)
            sessionStats.maxPower = max(sessionStats.maxPower, p)
        }
        if let s = data.speed, s > 0 { 
            speedReadings.append(s)
            sessionStats.maxSpeed = max(sessionStats.maxSpeed, s)
        }
        if let c = data.cadence, c > 0 { 
            cadenceReadings.append(c)
            sessionStats.maxCadence = max(sessionStats.maxCadence, c)
        }
        
        // Log detailed data points every 10 records to avoid log spam
        if sessionStats.dataPointsCollected % 10 == 0 {
            logger.debug("Data point batch recorded", source: "TrainerSessionManager", metadata: [
                "total_points": sessionStats.dataPointsCollected,
                "hr_readings": heartRateReadings.count,
                "power_readings": powerReadings.count,
                "current_hr": data.heartRate as Any,
                "current_power": data.power as Any
            ])
        }
        
        if sessionStats.dataPointsCollected % TrainingConstants.Session.statsUpdateInterval == 0 { 
            updateRunningStatistics() 
        }
        delegate?.trainerSessionDidRecordData(data)
    }

    func resetSession() { 
        logger.info("Trainer session reset", source: "TrainerSessionManager", metadata: [
            "previous_state": sessionState.rawValue,
            "data_points": sessionStats.dataPointsCollected
        ])
        sessionTimer?.invalidate()
        resetSessionData()
        sessionState = .inactive
        delegate?.trainerSessionDidReset() 
    }

    private func resetSessionData() {
        sessionStats = TrainingSessionStats(); sessionStartTime = nil; sessionDuration = 0; pauseStartTime = nil; totalPausedTime = 0
        collectedData.removeAll(); heartRateReadings.removeAll(); powerReadings.removeAll(); speedReadings.removeAll(); cadenceReadings.removeAll()
    }

    private func startSessionTimer() { sessionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.updateSessionDuration() } }

    private func updateSessionDuration() { guard let start = sessionStartTime else { return }; let raw = Date().timeIntervalSince(start); sessionDuration = raw - totalPausedTime; sessionStats.duration = sessionDuration; delegate?.trainerSessionDidUpdateDuration(sessionDuration) }

    private func updateRunningStatistics() {
        if !heartRateReadings.isEmpty { sessionStats.averageHeartRate = heartRateReadings.reduce(0,+) / Double(heartRateReadings.count) }
        if !powerReadings.isEmpty { sessionStats.averagePower = Double(powerReadings.reduce(0,+)) / Double(powerReadings.count) }
        if !speedReadings.isEmpty { sessionStats.averageSpeed = speedReadings.reduce(0,+) / Double(speedReadings.count) }
        if !cadenceReadings.isEmpty { sessionStats.averageCadence = cadenceReadings.reduce(0,+) / Double(cadenceReadings.count) }
        if sessionStats.averagePower > 0 && sessionStats.duration > 0 { sessionStats.totalEnergyExpended = (sessionStats.averagePower * sessionStats.duration) / 3600.0 }
    }

    private func calculateFinalStatistics() { updateRunningStatistics() }
}

