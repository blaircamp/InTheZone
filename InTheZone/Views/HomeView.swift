import SwiftUI
import CoreBluetooth

struct HomeView: View {
    @EnvironmentObject var bluetoothService: BluetoothService
    @EnvironmentObject var sessionManager: SessionManager
    @State private var showingDeviceSelection = false
    @AppStorage("useWatchAppForSessions") private var useWatchAppForSessions: Bool = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Connection Status Card
                    connectionStatusCard
                    
                    // Session Control Card
                    sessionControlCard
                    
                    Spacer(minLength: 20)
                }
                .padding()
            }
            .navigationTitle("Home")
            .background(Color(.systemGroupedBackground))
            .sheet(isPresented: $showingDeviceSelection) {
                DeviceSelectionView()
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
            
            // Connect Button
            Button(action: {
                if bluetoothService.trainerConnectionStatus == .connected {
                    bluetoothService.disconnect()
                } else {
                    showingDeviceSelection = true
                }
            }) {
                HStack {
                    Image(systemName: bluetoothService.trainerConnectionStatus == .connected ? "xmark.circle.fill" : "plus.circle.fill")
                    Text(bluetoothService.trainerConnectionStatus == .connected ? "Disconnect" : "Connect Device")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(bluetoothService.trainerConnectionStatus == .connected ? Color("SoftRed") : Color("PrimaryGreen"))
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
}

#Preview {
    HomeView()
        .environmentObject(BluetoothService.shared)
        .environmentObject(SessionManager())
}