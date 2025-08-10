import Foundation

// Predictive heart rate zone controller using HR and HR' (bpm/s)
// Decides resistance adjustments to keep HR within target band using a prediction horizon.
struct HeartRateZoneControllerConfig {
    var horizonSeconds: Double = 7.0     // prediction horizon
    var deadbandBPM: Double = 2.0        // extra margin to avoid chatter
    var consecutiveNeeded: Int = 2        // hysteresis samples
    var minChangeInterval: TimeInterval = 5.0 // seconds between resistance changes
    var maxStepPerChange: Int = 3        // max increments per action (increased for 0-31 range)
    var bpmPerIncrement: Double = 2.0    // mapping of bpm error to one increment (more responsive)
    var gainUp: Double = 0.8             // proportional gain when HR too low (increased)
    var gainDown: Double = 0.8           // proportional gain when HR too high (increased)
    var adaptiveSteps: Bool = true       // enable adaptive step sizing based on error magnitude
    var emergencyStepMultiplier: Double = 2.0 // multiply steps for large HR errors (>10 bpm)
    
    // Learning parameters
    var enableLearning: Bool = true      // enable adaptive learning
    var learningRate: Double = 0.1       // how fast to adapt (0.0-1.0)
    var minLearningSteps: Int = 5        // minimum data points needed to start learning
    var effectivenessDecayFactor: Double = 0.95 // decay old effectiveness scores
    var evaluationWindow: TimeInterval = 10.0 // reduced from 15s to avoid interference
}

// Learning data for resistance changes
struct ResistanceChangeRecord {
    let timestamp: Date
    let hrBefore: Double
    let hrTarget: Double
    let resistanceChange: Int
    let direction: Int // -1 decrease, +1 increase
    var hrAfter: Double? = nil
    var effectiveness: Double? = nil // calculated after HR response is observed
}

final class HeartRateZoneController {
    private var config: HeartRateZoneControllerConfig
    private var lastDecisionTime: TimeInterval = 0
    private var consecutiveOutOfBand: Int = 0
    private var lastDirection: Int = 0 // -1 decrease, +1 increase, 0 none
    
    // Learning system
    private var recentChanges: [ResistanceChangeRecord] = []
    private var learnedStepEffectiveness: [String: Double] = [:] // "direction:stepSize" -> effectiveness
    private var totalLearningPoints: Int = 0

    init(config: HeartRateZoneControllerConfig = HeartRateZoneControllerConfig()) {
        self.config = config
    }

    func reset() {
        lastDecisionTime = 0
        consecutiveOutOfBand = 0
        lastDirection = 0
        recentChanges.removeAll()
        // Keep learned effectiveness but decay it
        for key in learnedStepEffectiveness.keys {
            learnedStepEffectiveness[key] = (learnedStepEffectiveness[key] ?? 0) * config.effectivenessDecayFactor
        }
    }
    
    // MARK: - Learning System
    
    /// Update the learning system with current HR to evaluate recent resistance changes
    func updateLearning(currentHR: Double) {
        guard config.enableLearning else { return }
        
        let now = Date()
        
        // Update recent changes with HR response and calculate effectiveness
        for i in recentChanges.indices {
            var change = recentChanges[i]
            
            // Only evaluate changes that are old enough to see HR response and not interfered with
            let timeElapsed = now.timeIntervalSince(change.timestamp)
            if change.hrAfter == nil && timeElapsed >= config.evaluationWindow {
                // Check if there were other resistance changes within evaluation window that could interfere
                let hasInterference = recentChanges.contains { otherChange in
                    otherChange.timestamp != change.timestamp && 
                    abs(otherChange.timestamp.timeIntervalSince(change.timestamp)) < config.evaluationWindow
                }
                
                if hasInterference {
                    // Skip this evaluation due to interference, but don't exclude it permanently
                    continue
                }
                change.hrAfter = currentHR
                
                // Calculate effectiveness: how well did this change move HR toward target?
                let hrErrorBefore = abs(change.hrBefore - change.hrTarget)
                let hrErrorAfter = abs(currentHR - change.hrTarget)
                
                // Effectiveness: positive if we improved, negative if we made it worse
                let improvement = hrErrorBefore - hrErrorAfter
                let maxPossibleImprovement = hrErrorBefore // normalize by initial error
                change.effectiveness = maxPossibleImprovement > 0 ? improvement / maxPossibleImprovement : 0
                
                // Store this learning point
                let stepKey = "\(change.direction):\(abs(change.resistanceChange))"
                updateLearnedEffectiveness(for: stepKey, effectiveness: change.effectiveness!)
                
                recentChanges[i] = change
                totalLearningPoints += 1
                
                // Log learning progress (using SessionLogger for consistency)
                SessionLogger.shared.info("Learning effectiveness recorded", source: "HeartRateZoneController", metadata: [
                    "resistance_change": change.resistanceChange,
                    "direction": change.direction,
                    "effectiveness": change.effectiveness!,
                    "hr_before": change.hrBefore,
                    "hr_after": currentHR,
                    "hr_target": change.hrTarget
                ])
            }
        }
        
        // Clean up old records (keep only recent ones for efficiency)
        let cutoff = now.addingTimeInterval(-60) // keep 1 minute of history
        recentChanges.removeAll { $0.timestamp < cutoff }
    }
    
    private func updateLearnedEffectiveness(for stepKey: String, effectiveness: Double) {
        let currentValue = learnedStepEffectiveness[stepKey] ?? 0.0
        // Exponential moving average
        learnedStepEffectiveness[stepKey] = currentValue * (1 - config.learningRate) + effectiveness * config.learningRate
    }
    
    /// Get the optimal step size based on learned effectiveness
    private func getOptimalStepSize(direction: Int, baseSteps: Int) -> Int {
        guard config.enableLearning && totalLearningPoints >= config.minLearningSteps else {
            return baseSteps // not enough data to learn yet
        }
        
        var bestStepSize = baseSteps
        var bestEffectiveness = -1.0
        
        // Try different step sizes and find the most effective one
        for stepSize in 1...config.maxStepPerChange {
            let stepKey = "\(direction):\(stepSize)"
            if let effectiveness = learnedStepEffectiveness[stepKey], effectiveness > bestEffectiveness {
                bestEffectiveness = effectiveness
                bestStepSize = stepSize
            }
        }
        
        SessionLogger.shared.debug("Optimal step size selected", source: "HeartRateZoneController", metadata: [
            "direction": direction,
            "optimal_step": bestStepSize,
            "effectiveness": bestEffectiveness,
            "total_learning_points": totalLearningPoints
        ])
        return bestStepSize
    }
    
    /// Record a resistance change for learning
    private func recordResistanceChange(hrBefore: Double, hrTarget: Double, resistanceChange: Int, direction: Int) {
        guard config.enableLearning else { return }
        
        let record = ResistanceChangeRecord(
            timestamp: Date(),
            hrBefore: hrBefore,
            hrTarget: hrTarget,
            resistanceChange: resistanceChange,
            direction: direction
        )
        recentChanges.append(record)
    }

    // Decide on resistance change.
    // Inputs:
    //  - hr: filtered heart rate (bpm)
    //  - dhr: heart rate slope (bpm/s)
    //  - now: current time
    //  - zoneLow, zoneHigh: target band
    //  - current: current resistance
    //  - range: (min, max, inc)
    //  - cadence: current cadence (RPM), optional
    //  - cadenceThreshold: minimum cadence threshold, optional
    // Returns: new resistance if a change is warranted, else nil.
    func decide(hr: Double,
                dhr: Double,
                now: Date,
                zoneLow: Double,
                zoneHigh: Double,
                current: Int,
                range: (min: Int, max: Int, increment: Int),
                cadence: Double? = nil,
                cadenceThreshold: Double? = nil) -> Int? {
        let t = now.timeIntervalSince1970
        let eps = config.deadbandBPM
        let pred = hr + dhr * config.horizonSeconds
        
        // Check for cadence emergency override first
        // If cadence is too low, we should reduce resistance regardless of HR
        if let currentCadence = cadence, let minCadence = cadenceThreshold {
            if currentCadence > 0 && currentCadence < minCadence && current > range.min {
                // Cadence too low and we have room to reduce resistance
                // Only override if we're not already trying to increase HR significantly
                if hr >= zoneLow - 5 { // Within 5 bpm of zone or already in/above zone
                    SessionLogger.shared.info("Cadence override: reducing resistance", source: "HeartRateZoneController", metadata: [
                        "cadence": currentCadence,
                        "min_cadence": minCadence,
                        "hr": hr,
                        "zone_low": zoneLow,
                        "current_resistance": current
                    ])
                    
                    // Calculate reduction based on how far below threshold we are
                    let cadenceDeficit = minCadence - currentCadence
                    let reductionSteps = max(1, min(3, Int(cadenceDeficit / 10))) // 1-3 steps based on deficit
                    let deltaIncrements = -reductionSteps * range.increment
                    let newValue = max(range.min, current + deltaIncrements)
                    
                    if newValue != current {
                        lastDecisionTime = t
                        return newValue
                    }
                }
            }
        }

        // Determine direction: -1 means need to reduce HR (pred too high) => decrease resistance
        // +1 means need to raise HR (pred too low) => increase resistance
        var dir = 0
        if hr > zoneHigh + eps && pred > zoneHigh + eps { dir = -1 }
        else if hr < zoneLow - eps && pred < zoneLow - eps { 
            // Only increase resistance if cadence is sufficient
            if let currentCadence = cadence, let minCadence = cadenceThreshold {
                // Don't increase resistance if cadence is near or below threshold
                if currentCadence > 0 && currentCadence < minCadence + 10 {
                    SessionLogger.shared.debug("Skipping resistance increase due to low cadence", source: "HeartRateZoneController", metadata: [
                        "cadence": currentCadence,
                        "min_cadence": minCadence,
                        "hr": hr
                    ])
                    dir = 0 // Cancel the increase
                } else {
                    dir = +1
                }
            } else {
                dir = +1
            }
        }

        if dir == 0 {
            // inside band or disagreement; reset hysteresis
            consecutiveOutOfBand = 0
            lastDirection = 0
            return nil
        }

        // Hysteresis: require same direction consecutively
        if dir == lastDirection {
            consecutiveOutOfBand += 1
        } else {
            consecutiveOutOfBand = 1
            lastDirection = dir
        }
        if consecutiveOutOfBand < config.consecutiveNeeded { return nil }

        // Rate limit
        if lastDecisionTime > 0 && (t - lastDecisionTime) < config.minChangeInterval { return nil }

        // Compute error to target (improved for large deviations)
        let target: Double
        if pred < zoneLow {
            // Below zone: target middle-lower part for gentler approach
            target = zoneLow + (zoneHigh - zoneLow) * 0.3
        } else if pred > zoneHigh {
            // Above zone: target middle-upper part for gentler approach  
            target = zoneLow + (zoneHigh - zoneLow) * 0.7
        } else {
            // Within zone: target the center
            target = (zoneLow + zoneHigh) / 2.0
        }
        let error = pred - target // positive if predicted above target

        // Map error to increments with directional gains
        let gain = (dir > 0) ? config.gainUp : config.gainDown
        let rawSteps = gain * error / config.bpmPerIncrement
        var steps = Int(rawSteps.rounded())

        // Adaptive step sizing based on error magnitude
        if config.adaptiveSteps {
            let errorMagnitude = abs(error)
            if errorMagnitude > 10.0 { // Large error (>10 bpm off target)
                steps = Int(Double(steps) * config.emergencyStepMultiplier)
            } else if errorMagnitude > 5.0 { // Medium error (5-10 bpm)
                steps = Int(Double(steps) * 1.5)
            }
            // Small errors (< 5 bpm) use normal step size
        }

        // Ensure steps have correct sign and are at least one increment in chosen direction
        if steps == 0 { steps = dir }
        steps = max(-config.maxStepPerChange, min(config.maxStepPerChange, steps))

        // Apply learning: get optimal step size based on historical effectiveness
        let learnedSteps = getOptimalStepSize(direction: dir, baseSteps: abs(steps))
        steps = dir * learnedSteps

        // Convert to resistance increments (respect device increment)
        let deltaIncrements = steps * range.increment
        let newValue = max(range.min, min(range.max, current + deltaIncrements))

        if newValue == current { return nil }

        // Record this change for learning (target is middle of zone for simplicity)
        let targetHR = (zoneLow + zoneHigh) / 2.0
        recordResistanceChange(hrBefore: hr, hrTarget: targetHR, resistanceChange: deltaIncrements, direction: dir)

        lastDecisionTime = t
        consecutiveOutOfBand = 0 // reset after action
        lastDirection = 0
        return newValue
    }
    
    // MARK: - Debug & Statistics
    
    /// Get learning statistics for debugging
    func getLearningStats() -> [String: Any] {
        return [
            "totalLearningPoints": totalLearningPoints,
            "recentChanges": recentChanges.count,
            "learnedEffectiveness": learnedStepEffectiveness,
            "isLearning": config.enableLearning && totalLearningPoints >= config.minLearningSteps
        ]
    }
}

