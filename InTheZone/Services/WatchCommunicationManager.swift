import Foundation
import Combine
import WatchConnectivity

final class WatchCommunicationManager: NSObject, ObservableObject {
    @Published var isReachable = false
    @Published var lastHeartRate: Double = 0
    @Published var lastUpdate: Date?
    @Published var sessionStartTime: Date?

    let session = WCSession.default
    let heartRatePublisher = PassthroughSubject<Double, Never>()
    let sessionCommandPublisher = PassthroughSubject<String, Never>() // "start" or "stop"

    override init() {
        super.init()
        if WCSession.isSupported() {
            session.delegate = self
            session.activate()
        }
    }

    // Optional: sender from phone to watch if needed
    func sendMessage(_ message: [String: Any]) {
        guard session.activationState == .activated else { return }
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { _ in }
        } else {
            // Fall back to background delivery
            session.transferUserInfo(message)
            // For state-like messages, also publish as application context
            do { try session.updateApplicationContext(message) } catch {}
        }
    }
    
    func sendResistanceChange(oldLevel: Int, newLevel: Int) {
        let direction = newLevel > oldLevel ? "increase" : "decrease"
        let message: [String: Any] = [
            "type": "resistance",
            "direction": direction,
            "newLevel": newLevel,
            "oldLevel": oldLevel
        ]
        sendMessage(message)
    }
    
    func sendSessionStart(startTime: Date) {
        sessionStartTime = startTime
        let message: [String: Any] = [
            "type": "sessionSync",
            "command": "start",
            "startTime": startTime.timeIntervalSince1970
        ]
        sendMessage(message)
    }
    
    func sendSessionStop() {
        sessionStartTime = nil
        let message: [String: Any] = [
            "type": "sessionSync",
            "command": "stop"
        ]
        sendMessage(message)
    }
}

extension WatchCommunicationManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        // Check if we have any application context from Watch
        if !session.receivedApplicationContext.isEmpty {
            handleHRMessage(session.receivedApplicationContext)
        }
        DispatchQueue.main.async { self.isReachable = session.isReachable }
    }
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.isReachable = session.isReachable }
    }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    // Expect messages like { "type": "hr", "value": Double }
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        handleHRMessage(message)
    }
    
    // This delegate method is required when the Watch sends with a replyHandler
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        handleHRMessage(message)
        replyHandler(["status": "received"])
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        handleHRMessage(applicationContext)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        handleHRMessage(userInfo)
    }

    private func handleHRMessage(_ dict: [String: Any]) {
        // Check for session commands first
        if let type = dict["type"] as? String, type == "session", let command = dict["command"] as? String {
            DispatchQueue.main.async {
                self.sessionCommandPublisher.send(command)
                // Handle session start time from watch
                if command == "start", let startTime = dict["startTime"] as? TimeInterval {
                    self.sessionStartTime = Date(timeIntervalSince1970: startTime)
                } else if command == "stop" {
                    self.sessionStartTime = nil
                }
            }
            return
        }
        
        // Fast path for real-time messages
        if let type = dict["type"] as? String, type == "hr", let val = dict["value"] as? Double {
            // Update immediately on current queue, then notify on main
            self.lastHeartRate = val
            self.lastUpdate = Date()
            DispatchQueue.main.async {
                self.heartRatePublisher.send(val)
            }
        } else if let val = dict["heartRate"] as? Double { // match older app schema
            // Update immediately on current queue, then notify on main
            self.lastHeartRate = val
            self.lastUpdate = Date()
            DispatchQueue.main.async {
                self.heartRatePublisher.send(val)
            }
        }
    }
}

