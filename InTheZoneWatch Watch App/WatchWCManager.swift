import Foundation
import WatchConnectivity
import Combine
import WatchKit

enum SessionCommand {
    case start
    case stop
}

struct ResistanceChange {
    let direction: ResistanceDirection
    let newLevel: Int
    let timestamp: Date
}

enum ResistanceDirection {
    case increase
    case decrease
}

final class WatchWCManager: NSObject, ObservableObject {
    @Published var isReachable = false
    @Published var lastResistanceChange: ResistanceChange?
    @Published var sessionStartTime: Date?
    private let session = WCSession.default
    
    // Throttle heart rate messages to prevent flooding
    private var lastSentTime: Date = Date.distantPast
    private let messageInterval: TimeInterval = 0.5 // Send at most every 0.5 seconds for faster updates
    private var lastSentBPM: Double = 0

    // Outbound queue for messages when not reachable
    private var outboundQueue: [[String: Any]] = []

    override init() {
        super.init()
        if WCSession.isSupported() {
            session.delegate = self
            session.activate()
            // Try to set initial context immediately (may fail if not activated yet)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.pushInitialContext()
            }
        }
    }

    // Call after activation or reachability changes to send a minimal context
    private func pushInitialContext() {
        // Only update context if session is activated
        guard session.activationState == .activated else { return }
        
        // Mirror the older app's schema so the iOS app doesn't log "Application context data is nil"
        let ctx: [String: Any] = [
            "heartRate": 0.0,
            "timestamp": Date().timeIntervalSince1970
        ]
        do {
            try session.updateApplicationContext(ctx)
        } catch {
            // It's okay if context fails; it will be retried on next update
        }
    }

    func sendSessionCommand(_ command: SessionCommand) {
        guard session.activationState == .activated else { return }
        
        var payload: [String: Any] = [
            "type": "session",
            "command": command == .start ? "start" : "stop"
        ]
        
        // Include start time when starting a session
        if command == .start {
            let startTime = Date()
            sessionStartTime = startTime
            payload["startTime"] = startTime.timeIntervalSince1970
        } else {
            sessionStartTime = nil
        }
        
        if session.isReachable {
            // Send immediately for fastest response
            session.sendMessage(payload, replyHandler: nil) { _ in }
        } else {
            // Fall back to transferUserInfo for reliability
            session.transferUserInfo(payload)
        }
        
        // Also update application context as a backup
        do {
            try session.updateApplicationContext(payload)
        } catch { }
    }
    
    func sendHeartRate(_ bpm: Double) {
        let now = Date()
        let timeSinceLastSend = now.timeIntervalSince(lastSentTime)
        let bpmChanged = abs(bpm - lastSentBPM) > 1.0 // Send if BPM changed by 1 or more
        
        // More strict activation check to avoid unnecessary attempts
        guard session.activationState == .activated else { 
            // Session not ready yet, queue for later
            let payload: [String: Any] = ["type": "hr", "value": bpm]
            outboundQueue.append(payload)
            if outboundQueue.count > 20 { outboundQueue.removeFirst(outboundQueue.count - 20) }
            return 
        }
        
        // Send immediately if BPM changed, or if enough time has passed
        guard timeSinceLastSend >= messageInterval || bpmChanged else { return }

        let payload: [String: Any] = ["type": "hr", "value": bpm]
        
        // For fastest delivery, prioritize sendMessage over application context
        if session.isReachable {
            // sendMessage is the fastest method - near real-time
            session.sendMessage(payload, replyHandler: nil) { _ in 
                // Silently handle errors
            }
            
            // Only update context occasionally as a backup (every 2 seconds)
            if timeSinceLastSend >= 2.0 {
                do { 
                    try session.updateApplicationContext(["heartRate": bpm, "timestamp": now.timeIntervalSince1970])
                } catch { }
            }
        } else {
            // Not reachable: fall back to transferUserInfo (reliable, async, won't generate errors)
            session.transferUserInfo(payload)
            // Save to queue for later delivery
            outboundQueue.append(payload)
            if outboundQueue.count > 20 { outboundQueue.removeFirst(outboundQueue.count - 20) }
        }
        
        lastSentTime = now
        lastSentBPM = bpm
    }

    private func drainQueueIfNeeded() {
        // Check reachability before attempting to drain queue
        guard session.isReachable else { return }
        guard !outboundQueue.isEmpty else { return }
        
        // Send only the most recent message from the queue to avoid flooding
        if let mostRecent = outboundQueue.last {
            session.sendMessage(mostRecent, replyHandler: nil) { _ in 
                // Silently handle any errors
            }
        }
        // Clear the queue after attempting to send the most recent
        outboundQueue.removeAll()
    }
}

extension WatchWCManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { self.isReachable = session.isReachable }
        // Send an initial context and try to drain any queued messages
        pushInitialContext()
        drainQueueIfNeeded()
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.isReachable = session.isReachable }
        drainQueueIfNeeded()
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        DispatchQueue.main.async {
            self.handleIncomingMessage(message)
        }
    }
    
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any]) {
        DispatchQueue.main.async {
            self.handleIncomingMessage(userInfo)
        }
    }
    
    private func handleIncomingMessage(_ message: [String: Any]) {
        guard let type = message["type"] as? String else { return }
        
        switch type {
        case "resistance":
            if let directionStr = message["direction"] as? String,
               let newLevel = message["newLevel"] as? Int {
                let direction: ResistanceDirection = directionStr == "increase" ? .increase : .decrease
                let change = ResistanceChange(
                    direction: direction,
                    newLevel: newLevel,
                    timestamp: Date()
                )
                lastResistanceChange = change
                
                // Trigger haptic feedback
                triggerResistanceFeedback(direction: direction)
            }
        case "sessionSync":
            if let command = message["command"] as? String {
                if command == "start", let startTime = message["startTime"] as? TimeInterval {
                    sessionStartTime = Date(timeIntervalSince1970: startTime)
                } else if command == "stop" {
                    sessionStartTime = nil
                }
            }
        default:
            break
        }
    }
    
    private func triggerResistanceFeedback(direction: ResistanceDirection) {
        let feedback = WKHapticType.click
        
        switch direction {
        case .increase:
            // Two quick pulses for increase
            WKInterfaceDevice.current().play(feedback)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                WKInterfaceDevice.current().play(feedback)
            }
        case .decrease:
            // One longer pulse for decrease
            WKInterfaceDevice.current().play(.notification)
        }
    }
}

