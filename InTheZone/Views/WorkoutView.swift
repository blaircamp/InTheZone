import SwiftUI
import Charts
import UIKit

struct WorkoutView: View {
    @EnvironmentObject var bluetoothService: BluetoothService
    @EnvironmentObject var sessionManager: SessionManager
    @StateObject private var watchManager = WatchCommunicationManager()
    @State private var selectedMetricsTab = 0 // 0 = Live Metrics, 1 = Live Chart
    @AppStorage("useWatchAppForSessions") private var useWatchAppForSessions: Bool = false
    
    // Long press state for resistance control
    @State private var isLongPressing = false
    @State private var longPressTimer: Timer?
    
    // Session timer state
    @State private var sessionTimer: Timer?
    @State private var sessionStartTime: Date?
    
    // Computed property to calculate session duration from start time
    private var calculatedSessionDuration: TimeInterval {
        guard let startTime = sessionStartTime ?? watchManager.sessionStartTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }
    
    // Helper function to format metric values with max 2 decimal places
    private func formatMetricValue(_ value: Double) -> String {
        // If the value is a whole number, show no decimals
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        }
        // Otherwise show up to 2 decimal places, removing trailing zeros
        let formatted = String(format: "%.2f", value)
        // Remove trailing zeros after decimal point
        if formatted.contains(".") {
            let trimmed = formatted.replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
            return trimmed
        }
        return formatted
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Control Point Message
                    if let msg = bluetoothService.lastControlPointMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                    }
                    
                    // Metrics/Chart Tabbed Section
                    metricsTabSection
                    
                    // Session Control Section
                    sessionControlSection
                    
                    // Resistance Control Section
                    resistanceControlSection
                    
                    Spacer(minLength: 20)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Workouts")
            .onDisappear {
                // Clean up timer when view disappears
                sessionTimer?.invalidate()
                sessionTimer = nil
            }
            .onReceive(watchManager.sessionCommandPublisher) { command in
                // Handle session commands from watch
                if command == "start" {
                    if !bluetoothService.isSessionActive {
                        startTrainingSession()
                    }
                } else if command == "stop" {
                    if bluetoothService.isSessionActive {
                        stopTrainingSession()
                    }
                }
            }
            .onAppear {
                // Sync session state if watch has an active session
                if let watchStartTime = watchManager.sessionStartTime, 
                   !bluetoothService.isSessionActive {
                    // Watch has a session, iOS doesn't - sync them
                    sessionStartTime = watchStartTime
                    bluetoothService.startSession()
                    sessionManager.startSession()
                    
                    // Start display timer
                    sessionTimer?.invalidate()
                    sessionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                        // Timer just triggers UI updates
                    }
                }
            }



            .alert("System Error", isPresented: $bluetoothService.showSystemError) {
                Button("OK") { 
                    bluetoothService.showSystemError = false 
                }
            } message: {
                Text(bluetoothService.systemErrorMessage ?? "An error occurred")
            }
        }
    }

    // MARK: - Metrics/Chart Tabbed Section
    private var metricsTabSection: some View {
        VStack(spacing: 16) {
            // Segmented Control
            Picker("Metrics View", selection: $selectedMetricsTab) {
                Label("Metrics", systemImage: "speedometer")
                    .tag(0)
                Label("Chart", systemImage: "chart.line.uptrend.xyaxis")
                    .tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .accentColor(Color("PrimaryGreen"))
            
            // Content based on selection
            if selectedMetricsTab == 0 {
                liveMetricsContent
            } else {
                liveChartContent
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    // MARK: - Live Metrics Content
    private var liveMetricsContent: some View {
        VStack(spacing: 16) {
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                metricCard(
                    title: "Heart Rate",
                    value: bluetoothService.trainerData.heartRate.map { String($0) } ?? "--",
                    unit: "BPM",
                    color: Color("SoftRed"),
                    icon: "heart.fill"
                )
                
                metricCard(
                    title: "Power",
                    value: bluetoothService.trainerData.power.map { String($0) } ?? "--",
                    unit: "W",
                    color: Color("BrightOrange"),
                    icon: "bolt.fill"
                )
                
                metricCard(
                    title: "Cadence",
                    value: bluetoothService.trainerData.cadence.map { formatMetricValue($0) } ?? "--",
                    unit: "RPM",
                    color: Color("BrightBlue"),
                    icon: "speedometer"
                )
                
                metricCard(
                    title: "Speed",
                    value: bluetoothService.trainerData.speed.map { formatMetricValue($0) } ?? "--",
                    unit: "km/h",
                    color: Color("SecondaryGreen"),
                    icon: "gauge.high"
                )
            }
            
            if !bluetoothService.isSessionActive {
                Text("Data shown live but not recorded until session starts")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
                    .padding(.top, 8)
            }
        }
    }
    
    private func metricCard(title: String, value: String, unit: String, color: Color, icon: String) -> some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text(unit)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fontWeight(.medium)
                }
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 1)
    }
    
    // MARK: - Session Control Section
    private var sessionControlSection: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: bluetoothService.isSessionActive ? "record.circle.fill" : "pause.circle.fill")
                    .font(.title2)
                    .foregroundColor(bluetoothService.isSessionActive ? Color("PrimaryGreen") : .secondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Training Session")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if bluetoothService.isSessionActive {
                        Text(formatSessionDuration(calculatedSessionDuration))
                            .font(.system(.title3, design: .monospaced))
                            .foregroundColor(Color("PrimaryGreen"))
                            .fontWeight(.semibold)
                    } else {
                        Text("Session Inactive")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .fontWeight(.medium)
                    }
                }
                
                Spacer()
            }
            
            if bluetoothService.trainerConnectionStatus == .connected {
                Button(action: {
                    if bluetoothService.isSessionActive {
                        stopTrainingSession()
                    } else {
                        startTrainingSession()
                    }
                }) {
                    HStack {
                        Image(systemName: bluetoothService.isSessionActive ? "stop.circle.fill" : "play.circle.fill")
                        Text(bluetoothService.isSessionActive ? "Stop Session" : "Start Session")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(bluetoothService.isSessionActive ? Color("SoftRed") : Color("PrimaryGreen"))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
            } else {
                Text("Connect to a trainer to start a session")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    // MARK: - Resistance Control Section
    private var resistanceControlSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Resistance Control")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            
            Toggle("Auto Control", isOn: $bluetoothService.isAutoControlEnabled)
                .tint(Color("PrimaryGreen"))
            
            if bluetoothService.isAutoControlEnabled {
                autoControlInfo
            } else {
                jetblackStyleResistanceControl
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    private var autoControlInfo: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.title3)
                    .foregroundColor(Color("PrimaryGreen"))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Auto Control Active")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(Color("PrimaryGreen"))
                    
                    Text("Target Zone: \(Int(TrainingConstants.HeartRateZones.lower))–\(Int(TrainingConstants.HeartRateZones.upper)) bpm")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding()
            .background(Color("PrimaryGreen").opacity(0.1))
            .cornerRadius(8)
            
            // Show cadence control status if enabled
            if UserDefaults.standard.bool(forKey: "useCadenceControl") {
                HStack {
                    Image(systemName: "speedometer")
                        .font(.caption)
                        .foregroundColor(Color("SecondaryGreen"))
                    
                    Text("Cadence Protection: Min \(Int(UserDefaults.standard.double(forKey: "minCadenceThreshold"))) RPM")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if let cadence = bluetoothService.trainerData.cadence {
                        Text("\(formatMetricValue(cadence)) RPM")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(cadence < UserDefaults.standard.double(forKey: "minCadenceThreshold") ? Color("SoftRed") : Color("SecondaryGreen"))
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color("SecondaryGreen").opacity(0.05))
                .cornerRadius(6)
            }
            
            Text("Configure target zone in Settings → Heart Rate Zone")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var jetblackStyleResistanceControl: some View {
        let minVal = bluetoothService.resistanceRange?.min ?? TrainingConstants.Resistance.minimum
        let maxVal = bluetoothService.resistanceRange?.max ?? TrainingConstants.Resistance.maximum
        let stepSize = TrainingConstants.Resistance.stepSize  // Use configured step size
        let resistanceManager = bluetoothService.resistanceStateManager
        let displayResistance = resistanceManager.displayLevel
        
        return VStack(spacing: 16) {
            // Current resistance display with prominent styling
            VStack(spacing: 8) {
                Text("\(displayResistance)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(Color("PrimaryGreen"))
                
                Text("RESISTANCE LEVEL")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    Text("Range: \(minVal) - \(maxVal)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text("Step: \(stepSize)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fontWeight(.medium)
                    
                    if bluetoothService.zwiftClickConnected {
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 2) {
                            Image(systemName: "gamecontroller.fill")
                                .font(.caption2)
                            Text("Click")
                                .font(.caption2)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(Color("PrimaryGreen"))
                    }
                }
            }
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
            .background(Color(.systemGray6))
            .cornerRadius(16)
            
            // Jetblack-style control buttons with haptic feedback
            HStack(spacing: 0) {
                // Decrease button (left side) with long press
                Button(action: {
                    adjustResistance(by: -stepSize, min: minVal, max: maxVal, current: displayResistance)
                }) {
                    HStack {
                        Image(systemName: "minus.circle.fill")
                            .font(.title2)
                        Text("DECREASE")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: isLongPressing ? [Color("SoftRed").opacity(0.8), Color("SoftRed").opacity(0.6)] : [Color("SoftRed"), Color("SoftRed").opacity(0.8)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .scaleEffect(isLongPressing ? 0.95 : 1.0)
                    .disabled(displayResistance <= minVal)
                    .opacity(displayResistance <= minVal ? 0.5 : 1.0)
                    .animation(.easeInOut(duration: 0.1), value: isLongPressing)
                }
                .buttonStyle(PlainButtonStyle())
                .onLongPressGesture(minimumDuration: 0.5, maximumDistance: .infinity, pressing: { pressing in
                    if pressing {
                        startLongPress(adjustment: -stepSize, min: minVal, max: maxVal)
                    } else {
                        stopLongPress()
                    }
                }, perform: {})
                
                // Increase button (right side) with long press
                Button(action: {
                    adjustResistance(by: stepSize, min: minVal, max: maxVal, current: displayResistance)
                }) {
                    HStack {
                        Text("INCREASE")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: isLongPressing ? [Color("PrimaryGreen").opacity(0.8), Color("SecondaryGreen").opacity(0.8)] : [Color("PrimaryGreen"), Color("SecondaryGreen")]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .scaleEffect(isLongPressing ? 0.95 : 1.0)
                    .disabled(displayResistance >= maxVal)
                    .opacity(displayResistance >= maxVal ? 0.5 : 1.0)
                    .animation(.easeInOut(duration: 0.1), value: isLongPressing)
                }
                .buttonStyle(PlainButtonStyle())
                .onLongPressGesture(minimumDuration: 0.5, maximumDistance: .infinity, pressing: { pressing in
                    if pressing {
                        startLongPress(adjustment: stepSize, min: minVal, max: maxVal)
                    } else {
                        stopLongPress()
                    }
                }, perform: {})
            }
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            .animation(.easeInOut(duration: 0.1), value: isLongPressing)
            
            // Instructions text with dynamic feedback
            HStack(spacing: 4) {
                if isLongPressing {
                    Image(systemName: "hand.point.up.left.fill")
                        .font(.caption2)
                        .foregroundColor(Color("PrimaryGreen"))
                        .transition(.scale.combined(with: .opacity))
                }
                
                Text(isLongPressing ? "Rapid adjustment active" : "Tap buttons to adjust resistance • Hold for rapid changes")
                    .font(.caption2)
                    .foregroundColor(isLongPressing ? Color("PrimaryGreen") : .secondary)
                    .multilineTextAlignment(.center)
                    .animation(.easeInOut(duration: 0.2), value: isLongPressing)
            }
            .padding(.top, 4)
        }
    }
    
    // MARK: - Live Chart Content  
    private var liveChartContent: some View {
        VStack(spacing: 12) {
            Chart {
                // HR Zone band as a translucent background range
                let lower = TrainingConstants.HeartRateZones.lower
                let upper = TrainingConstants.HeartRateZones.upper
                RectangleMark(
                    xStart: .value("Start", bluetoothService.powerHistory.first?.timestamp ?? Date()),
                    xEnd: .value("End", bluetoothService.powerHistory.last?.timestamp ?? Date()),
                    yStart: .value("Zone Low", lower),
                    yEnd: .value("Zone High", upper)
                )
                .foregroundStyle(Color("SoftRed").opacity(0.15))
                .annotation(position: .overlay, alignment: .topTrailing) {
                    Text("HR Zone: \(Int(lower))–\(Int(upper)) bpm")
                        .font(.caption2)
                        .padding(4)
                        .background(.thinMaterial)
                        .cornerRadius(4)
                }

                ForEach(bluetoothService.powerHistory) { point in
                    if let p = point.power {
                        LineMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Power (W)", p)
                        )
                        .foregroundStyle(Color("BrightOrange"))
                        .interpolationMethod(.catmullRom)
                    }
                    if let hr = point.heartRate {
                        LineMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Heart Rate (bpm)", hr)
                        )
                        .foregroundStyle(Color("SoftRed"))
                        .interpolationMethod(.catmullRom)
                    }
                    if let cad = point.cadence {
                        LineMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Cadence (rpm)", cad)
                        )
                        .foregroundStyle(Color("BrightBlue"))
                        .interpolationMethod(.catmullRom)
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartLegend(position: .bottom, alignment: .center)
            .frame(height: 280)
        }
    }
    
    // MARK: - Session Management
    private func startTrainingSession() {
        // Start the session on iOS
        bluetoothService.startSession()
        sessionManager.startSession()
        
        // Set the session start time and send to watch
        let startTime = Date()
        sessionStartTime = startTime
        watchManager.sendSessionStart(startTime: startTime)
        
        // Start a timer to update the display every second
        sessionTimer?.invalidate()
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            // Timer just triggers UI updates, duration calculated from start time
        }
        
        // Launch Watch app if enabled
        if useWatchAppForSessions {
            launchWatchApp()
        }
    }
    
    private func stopTrainingSession() {
        bluetoothService.stopSession()
        sessionManager.endSession()
        
        // Stop the session timer and clear start time
        sessionTimer?.invalidate()
        sessionTimer = nil
        sessionStartTime = nil
        watchManager.sendSessionStop()
    }
    
    // Format session duration as HH:MM:SS
    private func formatSessionDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    private func launchWatchApp() {
        // Open the Watch app using WKExtension
        if let url = URL(string: "watch://com.campbell.InTheZone.watchkitapp") {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            }
        }
    }
    
    // MARK: - Resistance Control Helpers
    private func adjustResistance(by adjustment: Int, min: Int, max: Int, current: Int) {
        let newLevel = current + adjustment
        guard newLevel >= min && newLevel <= max else { return }
        
        // Haptic feedback with different intensities
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        bluetoothService.setResistance(newLevel)
    }
    
    private func startLongPress(adjustment: Int, min: Int, max: Int) {
        isLongPressing = true
        
        // Initial stronger haptic for long press start
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()
        
        // Start rapid adjustments
        longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
            let currentLevel = bluetoothService.resistanceStateManager.displayLevel
            let newLevel = currentLevel + adjustment
            
            guard newLevel >= min && newLevel <= max else {
                stopLongPress()
                return
            }
            
            // Lighter haptic for rapid adjustments
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            
            bluetoothService.setResistance(newLevel)
        }
    }
    
    private func stopLongPress() {
        isLongPressing = false
        longPressTimer?.invalidate()
        longPressTimer = nil
        
        // Final haptic to indicate long press ended
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
}

#Preview {
    WorkoutView()
        .environmentObject(BluetoothService.shared)
        .environmentObject(SessionManager())
}


