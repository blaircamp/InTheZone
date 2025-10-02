import Foundation
import SwiftUI

struct TrainingSession: Identifiable, Codable {
    let id: UUID
    let startTime: Date
    var endTime: Date?
    var metrics: [SessionMetric]
    var resistanceChanges: [ResistanceChange]

    // Simple aggregates
    var averageHeartRate: Double { let hrs = metrics.compactMap{ $0.heartRate }.filter{ $0 > 0 }; return hrs.isEmpty ? 0 : hrs.reduce(0,+)/Double(hrs.count) }
    var maxHeartRate: Double { metrics.compactMap{ $0.heartRate }.max() ?? 0 }
    var averagePower: Double { let p = metrics.map{ $0.power }.filter{ $0 > 0 }; return p.isEmpty ? 0 : p.reduce(0,+)/Double(p.count) }
    var maxPower: Double { Double(metrics.map{ $0.power }.max() ?? 0) }
    var averageCadence: Double { let c = metrics.compactMap{ $0.cadence }.filter{ $0 > 0 }; return c.isEmpty ? 0 : c.reduce(0,+)/Double(c.count) }
    var maxCadence: Double { metrics.compactMap{ $0.cadence }.max() ?? 0 }
    var totalWork: Double { // integrate power over time (approx)
        guard metrics.count > 1 else { return 0 }
        var w = 0.0
        for i in 1..<metrics.count { let dt = metrics[i].timestamp.timeIntervalSince(metrics[i-1].timestamp); let avg = (metrics[i-1].power + metrics[i].power)/2.0; w += avg * dt / 1000.0 }
        return w
    }
    var duration: TimeInterval { (endTime ?? Date()).timeIntervalSince(startTime) }

    init(startTime: Date = Date()) {
        self.id = UUID(); self.startTime = startTime; self.metrics = []; self.resistanceChanges = []
    }

    mutating func addMetric(_ metric: SessionMetric) { metrics.append(metric) }
    mutating func addResistanceChange(_ change: ResistanceChange) { resistanceChanges.append(change) }
    mutating func endSessionNow() { endTime = Date() }
}

struct SessionMetric: Codable {
    let timestamp: Date
    let heartRate: Double?
    let power: Double
    let cadence: Double?
    let resistance: Double
}

struct ResistanceChange: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let oldResistance: Double
    let newResistance: Double
    let reason: ResistanceChangeReason

    init(timestamp: Date = Date(), oldResistance: Double, newResistance: Double, reason: ResistanceChangeReason) {
        self.id = UUID(); self.timestamp = timestamp; self.oldResistance = oldResistance; self.newResistance = newResistance; self.reason = reason
    }
}

enum ResistanceChangeReason: String, Codable, CaseIterable { case manual = "Manual", warmup = "Warm-up", cooldown = "Cooldown"
    var color: Color { switch self { case .manual: return .blue; case .warmup: return .orange; case .cooldown: return .red } }
}

@MainActor
final class SessionManager: ObservableObject {
    @Published var savedSessions: [TrainingSession] = []
    @Published var currentSession: TrainingSession?
    @Published var isRecording = false

    private let userDefaults = UserDefaults.standard
    private let sessionsKey = "savedTrainingSessions"
    private let logger = SessionLogger.shared

    init() { loadSessions() }

    func startSession() { 
        currentSession = TrainingSession()
        isRecording = true
        logger.startSessionLogging()
        logger.info("Training session started", source: "SessionManager", metadata: [
            "session_id": currentSession?.id.uuidString ?? "unknown",
            "start_time": ISO8601DateFormatter().string(from: Date())
        ])
    }
    func endSession() { 
        guard var s = currentSession else { 
            logger.warning("Attempted to end session but no current session exists", source: "SessionManager")
            return 
        }
        s.endSessionNow()
        currentSession = s
        isRecording = false
        
        logger.info("Training session ended", source: "SessionManager", metadata: [
            "session_id": s.id.uuidString,
            "end_time": ISO8601DateFormatter().string(from: s.endTime ?? Date()),
            "duration": s.duration,
            "metrics_count": s.metrics.count,
            "resistance_changes": s.resistanceChanges.count,
            "avg_hr": s.averageHeartRate,
            "avg_power": s.averagePower
        ])
    }
    func saveCurrentSession() { 
        guard let s = currentSession else { 
            logger.warning("Attempted to save session but no current session exists", source: "SessionManager")
            return 
        }
        savedSessions.append(s)
        saveSessions()
        logger.info("Training session saved", source: "SessionManager", metadata: [
            "session_id": s.id.uuidString,
            "total_sessions": savedSessions.count
        ])
        logger.stopLogging()
        currentSession = nil
    }
    func discardCurrentSession() { 
        if let session = currentSession {
            logger.info("Training session discarded", source: "SessionManager", metadata: [
                "session_id": session.id.uuidString,
                "duration": session.duration,
                "metrics_count": session.metrics.count
            ])
        }
        logger.stopLogging()
        currentSession = nil
        isRecording = false
    }

    func recordMetric(heartRate: Double?, power: Double, cadence: Double?, resistance: Double) { 
        guard var s = currentSession else { 
            logger.debug("Attempted to record metric but no current session", source: "SessionManager")
            return 
        }
        s.addMetric(SessionMetric(timestamp: Date(), heartRate: heartRate, power: power, cadence: cadence, resistance: resistance))
        currentSession = s
        
        logger.debug("Metric recorded", source: "SessionManager", metadata: [
            "heart_rate": heartRate as Any,
            "power": power,
            "cadence": cadence as Any,
            "resistance": resistance,
            "total_metrics": s.metrics.count
        ])
    }
    func recordResistanceChange(oldResistance: Double, newResistance: Double, reason: ResistanceChangeReason) { 
        guard var s = currentSession else { 
            logger.debug("Attempted to record resistance change but no current session", source: "SessionManager")
            return 
        }
        s.addResistanceChange(ResistanceChange(oldResistance: oldResistance, newResistance: newResistance, reason: reason))
        currentSession = s
        
        logger.info("Resistance change recorded", source: "SessionManager", metadata: [
            "old_resistance": oldResistance,
            "new_resistance": newResistance,
            "reason": reason.rawValue,
            "total_changes": s.resistanceChanges.count
        ])
    }

    func deleteSession(_ session: TrainingSession) { savedSessions.removeAll{ $0.id == session.id }; saveSessions() }
    func deleteAllSessions() { savedSessions.removeAll(); saveSessions() }

    func exportAllSessionsAsCSV() -> String {
        var csv = "Session ID,Start Time,End Time,Duration (s),Avg HR,Max HR,Avg Power,Max Power,Avg Cadence,Max Cadence,Total Work (kJ),Resistance Changes\n"
        for s in savedSessions {
            let start = ISO8601DateFormatter().string(from: s.startTime)
            let end = s.endTime.map { ISO8601DateFormatter().string(from: $0) } ?? ""
            let dur = String(format: "%.1f", s.duration)
            let avgHR = String(Int(s.averageHeartRate))
            let maxHR = String(Int(s.maxHeartRate))
            let avgP = String(Int(s.averagePower))
            let maxP = String(Int(s.maxPower))
            let avgC = formatDoubleValue(s.averageCadence)
            let maxC = formatDoubleValue(s.maxCadence)
            let work = String(format: "%.2f", s.totalWork)
            let changes = s.resistanceChanges.count
            csv += "\(s.id.uuidString),\(start),\(end),\(dur),\(avgHR),\(maxHR),\(avgP),\(maxP),\(avgC),\(maxC),\(work),\(changes)\n"
        }
        return csv
    }
    
    private func formatDoubleValue(_ value: Double) -> String {
        // If the value is a whole number, show no decimals
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        }
        // Otherwise show up to 2 decimal places
        return String(format: "%.2f", value)
    }

    private func saveSessions() { if let data = try? JSONEncoder().encode(savedSessions) { userDefaults.set(data, forKey: sessionsKey) } }
    private func loadSessions() { if let data = userDefaults.data(forKey: sessionsKey), let arr = try? JSONDecoder().decode([TrainingSession].self, from: data) { savedSessions = arr } }
}

