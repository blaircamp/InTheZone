import Foundation
import HealthKit
import Combine

final class WatchHeartRateManager: NSObject, ObservableObject {
    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    @Published var currentHR: Double = 0
    @Published var isRunning: Bool = false

    let heartRatePublisher = PassthroughSubject<Double, Never>()
    private let logger = SessionLogger.shared

    // Prevent double-ending/finishing with better state management
    private var isEnding: Bool = false
    private let sessionQueue = DispatchQueue(label: "healthkit.session", qos: .userInitiated)
    
    // Track our own session lifecycle to prevent race conditions
    private var sessionLifecycleState: SessionLifecycleState = .notStarted
    
    private enum SessionLifecycleState {
        case notStarted
        case starting
        case active
        case ending
        case ended
    }

    private var hasEndedCollection: Bool = false
    private var hasFinishedWorkout: Bool = false

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            logger.error("HealthKit not available on device", source: "WatchHeartRateManager")
            DispatchQueue.main.async {
                completion(false)
            }
            return
        }

        // Request to SHARE workout type (required for HKWorkoutSession) and READ heart rate
        let typesToShare: Set<HKSampleType> = [HKObjectType.workoutType()]
        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!
        ]

        logger.info("Requesting HealthKit authorization", source: "WatchHeartRateManager")

        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { success, error in
            self.logger.info("HealthKit authorization result", source: "WatchHeartRateManager", metadata: [
                "success": success,
                "error": error?.localizedDescription as Any
            ])
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }

    func start() {
        guard !isRunning else {
            logger.warning("Attempted to start heart rate monitoring when already running", source: "WatchHeartRateManager")
            return
        }

        // Preflight: verify authorization before attempting to start a session
        let workoutStatus = healthStore.authorizationStatus(for: HKObjectType.workoutType())
        let hrType = HKObjectType.quantityType(forIdentifier: .heartRate)!
        let hrStatus = healthStore.authorizationStatus(for: hrType)
        if workoutStatus != .sharingAuthorized || hrStatus == .notDetermined {
            logger.error("HealthKit not authorized for required types", source: "WatchHeartRateManager", metadata: [
                "workout_share_status": workoutStatus.rawValue,
                "hr_read_status": hrStatus.rawValue
            ])
            return
        }

        logger.info("Starting heart rate monitoring", source: "WatchHeartRateManager", metadata: [
            "current_lifecycle_state": String(describing: sessionLifecycleState)
        ])

        // Clean up any previous session and reset state properly
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Check if there's an existing session to recover (this helps avoid SPRemoteInterface warnings)
            // We're not actually recovering it, just acknowledging it might exist
            if self.workoutSession != nil {
                self.logger.debug("Found existing workout session, will clean up first", source: "WatchHeartRateManager")
            }
            
            // Force cleanup and reset to proper starting state
            self.forceCleanupAndReset()
            
            // Small delay to ensure HealthKit state machine has time to reset
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.startWorkoutSession()
            }
        }
    }
    
    private func forceCleanupAndReset() {
        logger.debug("Force cleanup and reset", source: "WatchHeartRateManager", metadata: [
            "current_lifecycle_state": String(describing: sessionLifecycleState)
        ])
        
        // End any active session if it exists
        if let session = workoutSession {
            let currentHKState = session.state
            logger.debug("Force cleanup - current HK state", source: "WatchHeartRateManager", metadata: [
                "hk_state": currentHKState.rawValue
            ])
            
            switch currentHKState {
            case .running, .paused, .prepared:
                session.end()
            case .ended, .stopped, .notStarted:
                break // Already in final state
            @unknown default:
                break
            }
        }
        
        // Clean up references
        workoutSession?.delegate = nil
        builder?.delegate = nil
        workoutSession = nil
        builder = nil
        isEnding = false
        
        // Reset to proper starting state
        sessionLifecycleState = .notStarted
        
        // Reset UI state
        DispatchQueue.main.async {
            self.currentHR = 0
            self.isRunning = false
        }
    }

    private func startWorkoutSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.logger.info("Starting workout session", source: "WatchHeartRateManager", metadata: [
                "lifecycle_state": String(describing: self.sessionLifecycleState)
            ])
            
            // This should now always be .notStarted due to forceCleanupAndReset()
            guard self.sessionLifecycleState == .notStarted else {
                self.logger.error("Start called but session not in notStarted state", source: "WatchHeartRateManager", metadata: [
                    "lifecycle_state": String(describing: self.sessionLifecycleState)
                ])
                return
            }
        
            self.sessionLifecycleState = .starting
            self.hasEndedCollection = false
            self.hasFinishedWorkout = false
            
            // Note: SPRemoteInterface warning about no sessions is expected on first launch
            // This is a system-level log that occurs when no extended runtime sessions exist
            self.logger.info("Creating HealthKit workout session", source: "WatchHeartRateManager")
            
            let config = HKWorkoutConfiguration()
            config.activityType = .cycling
            config.locationType = .indoor
            
            do {
                self.workoutSession = try HKWorkoutSession(healthStore: self.healthStore, configuration: config)
                self.builder = self.workoutSession?.associatedWorkoutBuilder()
                self.builder?.dataSource = HKLiveWorkoutDataSource(healthStore: self.healthStore, workoutConfiguration: config)
                self.workoutSession?.delegate = self
                self.builder?.delegate = self
                let startDate = Date()
                
                self.logger.info("Starting HealthKit workout activity", source: "WatchHeartRateManager", metadata: [
                    "start_date": ISO8601DateFormatter().string(from: startDate)
                ])
                
                self.workoutSession?.startActivity(with: startDate)
                self.builder?.beginCollection(withStart: startDate) { [weak self] success, error in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        
                        if let error = error as NSError? {
                            self.logger.error("Failed to begin HealthKit collection", source: "WatchHeartRateManager", metadata: [
                                "error": error.localizedDescription,
                                "domain": error.domain,
                                "code": error.code
                            ])
                            // Reset state and clean up on error
                            self.sessionLifecycleState = .notStarted
                            self.cleanupSession()
                        } else {
                            self.logger.info("HealthKit collection started successfully", source: "WatchHeartRateManager", metadata: [
                                "success": success
                            ])
                            self.sessionLifecycleState = .active
                            self.isRunning = success
                        }
                    }
                }
            } catch {
                let nsError = error as NSError
                self.logger.error("Failed to create workout session", source: "WatchHeartRateManager", metadata: [
                    "error": nsError.localizedDescription,
                    "domain": nsError.domain,
                    "code": nsError.code
                ])
                self.sessionLifecycleState = .notStarted
                self.cleanupSession()
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Check our lifecycle state to prevent duplicate operations
            guard self.sessionLifecycleState == .active else {
                self.logger.debug("Stop called but session not active", source: "WatchHeartRateManager", metadata: [
                    "lifecycle_state": String(describing: self.sessionLifecycleState)
                ])
                // If we're already ending/ended, still try to clean up UI state
                if self.sessionLifecycleState == .ended {
                    DispatchQueue.main.async {
                        self.isRunning = false
                        self.currentHR = 0
                    }
                }
                return
            }
            
            self.sessionLifecycleState = .ending
            self.logger.info("Stopping watch heart rate monitoring", source: "WatchHeartRateManager")

            let end = Date()
            
            // Get the CURRENT state, don't cache it
            let currentHKState = self.workoutSession?.state ?? .notStarted
            self.logger.debug("Current HKWorkoutSession state before stop", source: "WatchHeartRateManager", metadata: [
                "hk_state": currentHKState.rawValue,
                "lifecycle_state": String(describing: self.sessionLifecycleState)
            ])

            // Only call end() if HealthKit shows the session can be ended
            if let session = self.workoutSession {
                switch currentHKState {
                case .running, .paused:
                    // Double-check the state right before calling end()
                    let currentState = session.state
                    if currentState == .running || currentState == .paused {
                        session.end()
                    } else {
                        // State changed, don't call end()
                        self.sessionLifecycleState = .ended
                    }
                case .prepared:
                    // For prepared state, we need to stop instead of end
                    session.stopActivity(with: end)
                case .ended, .stopped:
                    // Already ended, just update our state
                    self.sessionLifecycleState = .ended
                case .notStarted:
                    // Not started, just update our state
                    self.sessionLifecycleState = .ended
                @unknown default:
                    // Unknown state, just update our state
                    self.sessionLifecycleState = .ended
                }
            }

            // Always try to end the builder collection, regardless of session state
            if let builder = self.builder, !self.hasEndedCollection {
                self.logger.debug("Ending builder collection", source: "WatchHeartRateManager")
                self.hasEndedCollection = true
                builder.endCollection(withEnd: end) { [weak self] success, error in
                    DispatchQueue.main.async {
                        if let error = error {
self?.logger.error("Failed to end HealthKit collection", source: "WatchHeartRateManager", metadata: [
                        "error": error.localizedDescription
                    ])
                        } else {
                            self?.logger.info("HealthKit collection ended successfully", source: "WatchHeartRateManager", metadata: [
                                "success": success
                            ])
                        }

                        self?.finishWorkoutIfNeeded()
                    }
                }
            } else {
                self.logger.debug("No builder to end, proceeding to cleanup", source: "WatchHeartRateManager")
                DispatchQueue.main.async {
                    self.cleanupSession()
                }
            }
        }
    }
    
    private func cleanupSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.logger.debug("Cleaning up HealthKit session", source: "WatchHeartRateManager", metadata: [
                "lifecycle_state": String(describing: self.sessionLifecycleState)
            ])

            // Only attempt cleanup if we haven't already cleaned up
            guard self.sessionLifecycleState != .ended else {
                self.logger.debug("Session already cleaned up, skipping", source: "WatchHeartRateManager")
                // Still ensure UI is reset
                DispatchQueue.main.async {
                    self.currentHR = 0
                    self.isRunning = false
                }
                return
            }

            // Mark as ended first to prevent duplicate cleanup
            self.sessionLifecycleState = .ended

            // Get current HealthKit state and only end if necessary
            if let session = self.workoutSession {
                let currentHKState = session.state
                self.logger.debug("Current HK session state during cleanup", source: "WatchHeartRateManager", metadata: [
                    "hk_state": currentHKState.rawValue
                ])
                
                // Only try to end if HealthKit shows it can be ended
                switch currentHKState {
                case .running, .paused:
                    self.logger.debug("Calling session.end() during cleanup for state: \(currentHKState.rawValue)", source: "WatchHeartRateManager")
                    session.end()
                case .prepared:
                    self.logger.debug("Calling session.stopActivity() during cleanup for prepared state", source: "WatchHeartRateManager")
                    session.stopActivity(with: Date())
                case .ended, .stopped, .notStarted:
                    self.logger.debug("Session already ended or not started (state: \(currentHKState.rawValue)), skipping end() call", source: "WatchHeartRateManager")
                @unknown default:
                    self.logger.debug("Unknown session state during cleanup: \(currentHKState.rawValue)", source: "WatchHeartRateManager")
                }
            }

            // Clean up references
            self.workoutSession?.delegate = nil
            self.builder?.delegate = nil
            self.workoutSession = nil
            self.builder = nil
            self.isEnding = false
            self.hasEndedCollection = false
            self.hasFinishedWorkout = false

            // Reset UI state on main thread
            DispatchQueue.main.async {
                self.currentHR = 0
                self.isRunning = false
            }
        }
    }
}

extension WatchHeartRateManager: HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    // Ensure workout is finished only once
    private func finishWorkoutIfNeeded() {
        guard let builder = builder else {
            cleanupSession()
            return
        }
        guard !hasFinishedWorkout else { cleanupSession(); return }
        hasFinishedWorkout = true
        builder.finishWorkout { [weak self] workout, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.logger.error("Failed to finish workout", source: "WatchHeartRateManager", metadata: [
                        "error": error.localizedDescription
                    ])
                } else {
                    self?.logger.info("Workout finished successfully", source: "WatchHeartRateManager")
                }
                self?.isRunning = false
                self?.cleanupSession()
            }
        }
    }
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        DispatchQueue.main.async {
            self.logger.info("Workout session state changed", source: "WatchHeartRateManager", metadata: [
                "from_state": fromState.rawValue,
                "to_state": toState.rawValue,
                "lifecycle_state": String(describing: self.sessionLifecycleState),
                "timestamp": ISO8601DateFormatter().string(from: date)
            ])
            
            // Handle state transitions based on both HK state and our lifecycle state
            switch toState {
            case .running:
                if self.sessionLifecycleState == .starting {
                    self.sessionLifecycleState = .active
                }
                self.isRunning = true
                
            case .ended, .stopped:
                self.isRunning = false
                // Only finish workout if we haven't already started cleanup
                if self.sessionLifecycleState != .ending && self.sessionLifecycleState != .ended {
                    self.sessionLifecycleState = .ending
                    // Small delay to ensure state transition is complete
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.finishWorkoutIfNeeded()
                    }
                }
                
            case .notStarted, .prepared, .paused:
                // Handle these states but don't change lifecycle state unnecessarily
                break
                
            @unknown default:
                self.logger.debug("Unknown HKWorkoutSession state", source: "WatchHeartRateManager", metadata: [
                    "unknown_state": toState.rawValue
                ])
                break
            }
        }
    }
    
    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) { 
        DispatchQueue.main.async {
            let nsError = error as NSError
            
            // Check if this is the "already ended" error (code 3) - silently handle it
            let isAlreadyEndedError = nsError.domain == "com.apple.healthkit" && nsError.code == 3
            
            if isAlreadyEndedError {
                // This is expected when trying to end an already-ended session
                // Just clean up our state silently
                self.sessionLifecycleState = .ended
                self.isRunning = false
                self.currentHR = 0
                return
            }
            
            self.logger.error("Workout session failed", source: "WatchHeartRateManager", metadata: [
                "error": nsError.localizedDescription,
                "domain": nsError.domain,
                "code": nsError.code,
                "hk_state": workoutSession.state.rawValue,
                "lifecycle_state": String(describing: self.sessionLifecycleState)
            ])
            
            // Only clean up if we're not already in the process of ending/ended
            if self.sessionLifecycleState != .ending && self.sessionLifecycleState != .ended {
                self.isRunning = false
                self.sessionLifecycleState = .ending
                self.cleanupSession()
            }
        }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        logger.debug("Workout builder collected event", source: "WatchHeartRateManager")
    }

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard let hrType = HKObjectType.quantityType(forIdentifier: .heartRate), collectedTypes.contains(hrType) else { 
            logger.debug("Collected data but no heart rate type", source: "WatchHeartRateManager", metadata: [
                "collected_types": collectedTypes.map { $0.identifier }
            ])
            return 
        }
        
        if let stats = workoutBuilder.statistics(for: hrType), let q = stats.mostRecentQuantity() {
            let bpm = q.doubleValue(for: HKUnit(from: "count/min"))
            
            logger.debug("Heart rate data collected", source: "WatchHeartRateManager", metadata: [
                "heart_rate": bpm,
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ])
            
            DispatchQueue.main.async {
                self.currentHR = bpm
                self.heartRatePublisher.send(bpm)
            }
        }
    }
}

