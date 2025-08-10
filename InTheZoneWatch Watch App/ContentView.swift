//
//  ContentView.swift
//  InTheZoneWatch Watch App
//
//  Created by Blair Campbell on 2025-08-10.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var hrManager = WatchHeartRateManager()
    @StateObject private var wcManager = WatchWCManager()
    
    // Session timer state
    @State private var sessionTimer: Timer?
    @State private var sessionStartTime: Date?
    
    // Computed property to calculate duration from start time
    private var calculatedSessionDuration: TimeInterval {
        guard let startTime = sessionStartTime ?? wcManager.sessionStartTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }
    
    private var isSessionActive: Bool {
        (sessionStartTime ?? wcManager.sessionStartTime) != nil
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("In The Zone").font(.headline)
            
            // Session Duration Display
            if isSessionActive {
                Text(formatDuration(calculatedSessionDuration))
                    .font(.system(.title3, design: .monospaced))
                    .foregroundColor(.green)
                    .fontWeight(.semibold)
            }
            
            // Heart Rate Display
            HStack {
                Text("HR:")
                Text(hrText)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.red)
            }
            
            // Resistance Feedback Display
            if let resistanceChange = wcManager.lastResistanceChange {
                resistanceFeedbackView(resistanceChange)
            }
            HStack(spacing: 8) {
                Button(hrManager.isRunning ? "Stop" : "Start") {
                    print("Watch button tapped: \(hrManager.isRunning ? "Stop" : "Start")")
                    if hrManager.isRunning { 
                        print("Calling stop()")
                        hrManager.stop()
                        // Send stop session command to iOS
                        wcManager.sendSessionCommand(.stop)
                        // Stop session timer
                        stopSessionTimer()
                    } else {
                        print("Requesting authorization...")
                        hrManager.requestAuthorization { ok in
                            print("Authorization result: \(ok)")
                            if ok { 
                                print("Calling start()")
                                hrManager.start()
                                // Send start session command to iOS
                                wcManager.sendSessionCommand(.start)
                                // Start session timer
                                startSessionTimer()
                            } else {
                                print("Authorization denied")
                            }
                        }
                    }
                }
                .tint(hrManager.isRunning ? .red : .green)

                Image(systemName: wcManager.isReachable ? "iphone" : "iphone.slash")
                    .foregroundColor(wcManager.isReachable ? .green : .gray)
            }
        }
        .onReceive(hrManager.heartRatePublisher) { bpm in
            wcManager.sendHeartRate(bpm)
        }
        .onAppear {
            // Auto-start heart rate monitoring when the watch app launches
            if !hrManager.isRunning {
                hrManager.requestAuthorization { authorized in
                    if authorized {
                        hrManager.start()
                        wcManager.sendSessionCommand(.start)
                        startSessionTimer()
                    }
                }
            }
            
            // Sync with iOS session if one is already active
            if wcManager.sessionStartTime != nil {
                sessionStartTime = wcManager.sessionStartTime
                if sessionTimer == nil {
                    sessionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                        // Timer just triggers UI updates
                    }
                }
            }
        }
        .onDisappear {
            // Clean up timer when view disappears
            sessionTimer?.invalidate()
            sessionTimer = nil
        }
        .onChange(of: wcManager.sessionStartTime) { oldValue, newStartTime in
            // Sync when iOS sends session updates
            if let startTime = newStartTime {
                sessionStartTime = startTime
                if sessionTimer == nil {
                    sessionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                        // Timer just triggers UI updates
                    }
                }
            } else {
                // Session stopped on iOS
                stopSessionTimer()
            }
        }
        .padding()
    }

    private var hrText: String { hrManager.currentHR > 0 ? String(Int(hrManager.currentHR)) : "--" }
    
    private func resistanceFeedbackView(_ change: ResistanceChange) -> some View {
        HStack {
            Image(systemName: change.direction == .increase ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .foregroundColor(change.direction == .increase ? .orange : .blue)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Resistance \(change.direction == .increase ? "↑" : "↓")")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Text("Level \(change.newLevel)")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.gray.opacity(0.2))
        .cornerRadius(8)
    }
    
    private func startSessionTimer() {
        // Use the shared start time if available, otherwise set a new one
        if wcManager.sessionStartTime == nil {
            sessionStartTime = Date()
        } else {
            sessionStartTime = wcManager.sessionStartTime
        }
        
        sessionTimer?.invalidate()
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            // Timer just triggers UI updates, duration calculated from start time
        }
    }
    
    private func stopSessionTimer() {
        sessionTimer?.invalidate()
        sessionTimer = nil
        sessionStartTime = nil
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

#Preview {
    ContentView()
}
