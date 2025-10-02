import SwiftUI
import CoreBluetooth

struct HomeView: View {
    @EnvironmentObject var bluetoothService: BluetoothService
    @EnvironmentObject var sessionManager: SessionManager
    @State private var showDeviceList = false
    @AppStorage("useWatchAppForSessions") private var useWatchAppForSessions: Bool = false
    @StateObject private var zwiftClickService = ZwiftClickService.shared

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Connection Status Card
                    connectionStatusCard

                    // Device List Section
                    if showDeviceList {
                        deviceListSection
                    }
                    
                    // Live Metrics Card - shown when session is active
                    if bluetoothService.isSessionActive {
                        liveMetricsCard
                    }

                    // Session Control Card
                    if !showDeviceList {
                        sessionControlCard
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding()
            }
            .navigationTitle("Home")
            .background(Color(.systemGroupedBackground))
            .onDisappear {
                bluetoothService.stopScan()
                zwiftClickService.stopScan()
            }
        }
    }
    
    // MARK: - Connection Status Card
    private var connectionStatusCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: connectionStatusIcon)
                    .font(.title2)
                    .foregroundColor(connectionStatusColor)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connection Status")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(connectionStatusText)
                        .font(.subheadline)
                        .foregroundColor(connectionStatusColor)
                        .fontWeight(.medium)
                }
                
                Spacer()
            }
            
            if bluetoothService.isScanning {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Scanning for devices...")
                        .font(.caption)
                        .foregroundColor(Color("PrimaryGreen"))
                        .fontWeight(.medium)
                }
            }

            // Connect Button
            Button(action: {
                if bluetoothService.trainerConnectionStatus == .connected {
                    bluetoothService.disconnect()
                    showDeviceList = false
                    bluetoothService.stopScan()
                    zwiftClickService.stopScan()
                } else {
                    showDeviceList.toggle()
                    if showDeviceList {
                        bluetoothService.startScan()
                        zwiftClickService.startScan()
                    } else {
                        bluetoothService.stopScan()
                        zwiftClickService.stopScan()
                    }
                }
            }) {
                HStack {
                    Image(systemName: buttonIcon)
                        .fontWeight(.semibold)
                    Text(buttonText)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(buttonColor)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(!bluetoothService.isBluetoothReady || bluetoothService.trainerConnectionStatus == .connecting)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    // MARK: - Device List Section
    private var deviceListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Available Devices")
                .font(.headline)
                .padding(.horizontal)

            if bluetoothService.discoveredPeripherals.isEmpty && zwiftClickService.discoveredDevice == nil {
                emptyStateView
            } else {
                // Show trainers
                ForEach(bluetoothService.discoveredPeripherals, id: \.identifier) { peripheral in
                    deviceRow(peripheral, isTrainer: true)
                }

                // Show Zwift Click if discovered
                if let zwiftClick = zwiftClickService.discoveredDevice {
                    deviceRow(zwiftClick, isTrainer: false)
                }
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }

    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Text(bluetoothService.isScanning ? "Looking for devices..." : "No devices found. Make sure your trainer is on and in pairing mode.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }

    // MARK: - Device Row
    private func deviceRow(_ peripheral: CBPeripheral, isTrainer: Bool) -> some View {
        Button(action: {
            if isTrainer {
                bluetoothService.connect(to: peripheral)
            } else {
                zwiftClickService.connect(to: peripheral)
            }
            showDeviceList = false
            bluetoothService.stopScan()
            zwiftClickService.stopScan()
        }) {
            HStack(spacing: 16) {
                Image(systemName: isTrainer ? "bicycle" : "gamecontroller.fill")
                    .font(.title2)
                    .foregroundColor(isTrainer ? Color("PrimaryGreen") : Color("BrightOrange"))

                VStack(alignment: .leading, spacing: 4) {
                    Text(peripheral.name ?? "Unknown Device")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(isTrainer ? "Bike Trainer" : "Zwift Click Controller")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Session Control Card
    private var sessionControlCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: bluetoothService.isSessionActive ? "record.circle.fill" : "pause.circle.fill")
                    .font(.title2)
                    .foregroundColor(bluetoothService.isSessionActive ? Color("PrimaryGreen") : .secondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Training Session")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(bluetoothService.isSessionActive ? "Session Active" : "Session Inactive")
                        .font(.subheadline)
                        .foregroundColor(bluetoothService.isSessionActive ? Color("PrimaryGreen") : .secondary)
                        .fontWeight(.medium)
                }
                
                Spacer()
            }
            
            if bluetoothService.trainerConnectionStatus == .connected {
                Button(action: {
                    if bluetoothService.isSessionActive {
                        bluetoothService.stopSession()
                        sessionManager.endSession()
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
    
    // MARK: - Live Metrics Card
    private var liveMetricsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Live Metrics")
                .font(.headline)
                .padding(.horizontal)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                metricCard(
                    title: "Heart Rate",
                    value: bluetoothService.trainerData.heartRate.map { String($0) } ?? "--",
                    unit: "BPM",
                    color: Color("SoftRed"),
                    icon: "heart.fill",
                    source: bluetoothService.activeHeartRateSource
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
                    title: "Resistance",
                    value: bluetoothService.trainerData.resistance.map { String($0) } ?? "--",
                    unit: "Level",
                    color: Color("SecondaryGreen"),
                    icon: "dial.medium.fill"
                )
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }

    private func metricCard(title: String, value: String, unit: String, color: Color, icon: String, source: ActiveHeartRateSource? = nil) -> some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)

                if let source = source {
                    let sourceIcon = source == .watch ? "applewatch.watchface" : "bicycle"
                    let sourceText = source == .watch ? "Watch" : "Trainer"
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: sourceIcon)
                        Text(sourceText)
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(.systemGray6))
                    .cornerRadius(6)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Text(unit)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .fontWeight(.medium)
                }

                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }

    // MARK: - Connection Status Helpers
    private var connectionStatusIcon: String {
        switch bluetoothService.trainerConnectionStatus {
        case .connected: return "checkmark.circle.fill"
        case .connecting: return "antenna.radiowaves.left.and.right"
        default: return "exclamationmark.circle.fill"
        }
    }
    
    private var connectionStatusColor: Color {
        switch bluetoothService.trainerConnectionStatus {
        case .connected: return Color("PrimaryGreen")
        case .connecting: return Color("BrightOrange")
        default: return Color("SoftRed")
        }
    }
    
    private var connectionStatusText: String {
        if !bluetoothService.isBluetoothReady {
            return "Bluetooth Not Ready"
        }
        
        switch bluetoothService.trainerConnectionStatus {
        case .connected: return "Connected to Trainer"
        case .connecting: return "Connecting..."
        default: return "Not Connected"
        }
    }

    private var buttonIcon: String {
        if bluetoothService.trainerConnectionStatus == .connected {
            return "xmark.circle.fill"
        }
        return showDeviceList ? "xmark.circle.fill" : "magnifyingglass.circle.fill"
    }

    private var buttonText: String {
        if bluetoothService.trainerConnectionStatus == .connected {
            return "Disconnect"
        }
        return showDeviceList ? "Cancel Scan" : "Find Devices"
    }
    
    private var buttonColor: Color {
        if bluetoothService.trainerConnectionStatus == .connected {
            return Color("SoftRed")
        }
        return showDeviceList ? .gray : Color("PrimaryGreen")
    }

    // MARK: - Session Management
    private func startTrainingSession() {
        // Start the session on iOS
        bluetoothService.startSession()
        sessionManager.startSession()
        
        // Launch Watch app if enabled
        if useWatchAppForSessions {
            launchWatchApp()
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
}

#Preview {
    HomeView()
        .environmentObject(BluetoothService.shared)
        .environmentObject(SessionManager())
}