import Foundation
import Combine

// Simplified resistance state management with single resistance level
final class ResistanceStateManager: ObservableObject {
    
    // Published state that UI can observe
    @Published private(set) var resistanceLevel: Int = 0  // Current resistance level
    @Published private(set) var lastCommandTimestamp: Date? = nil
    
    // Configuration
    private let debounceInterval: TimeInterval = 0.3 // 300ms debounce between commands
    
    // MARK: - Public Interface
    
    /// Called when user requests resistance change by a specific amount (positive or negative)
    func requestResistanceChangeBySteps(_ steps: Int) -> Bool {
        let stepSize = TrainingConstants.Resistance.stepSize
        let actualChange = steps * stepSize
        let newLevel = resistanceLevel + actualChange
        return requestResistanceChange(to: newLevel)
    }
    
    /// Called when user requests resistance change
    func requestResistanceChange(to level: Int) -> Bool {
        let now = Date()
        
        // Debounce: prevent rapid successive commands
        if let lastTimestamp = lastCommandTimestamp,
           now.timeIntervalSince(lastTimestamp) < debounceInterval {
            SessionLogger.shared.debug("Resistance request debounced", source: "ResistanceStateManager", metadata: [
                "resistance_level": level,
                "time_since_last": now.timeIntervalSince(lastTimestamp)
            ])
            return false
        }
        
        // Update resistance level immediately for responsive UI
        lastCommandTimestamp = now
        resistanceLevel = level
        
        SessionLogger.shared.debug("Resistance change requested", source: "ResistanceStateManager", metadata: [
            "resistance_level": level
        ])
        return true
    }
    
    /// Called when trainer reports actual resistance level
    func updateResistanceLevel(_ level: Int) {
        resistanceLevel = level
        SessionLogger.shared.debug("Resistance level updated from trainer", source: "ResistanceStateManager", metadata: [
            "resistance_level": level
        ])
    }
    
    /// Check if we can accept new resistance commands
    func canAcceptNewCommand() -> Bool {
        guard let lastTimestamp = lastCommandTimestamp else { return true }
        return Date().timeIntervalSince(lastTimestamp) >= debounceInterval
    }
    
    /// Initialize resistance level from trainer (e.g., on connection)
    func initializeFromTrainer(_ level: Int) {
        SessionLogger.shared.debug("Initializing resistance from trainer", source: "ResistanceStateManager", metadata: [
            "resistance_level": level
        ])
        resistanceLevel = level
    }
    
    /// Reset state (e.g., on disconnection)
    func reset() {
        SessionLogger.shared.debug("Resistance state reset", source: "ResistanceStateManager")
        resistanceLevel = 0
        lastCommandTimestamp = nil
    }
    
    /// Get resistance level for UI display
    var displayLevel: Int {
        return resistanceLevel
    }
}