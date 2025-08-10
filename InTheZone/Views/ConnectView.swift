import SwiftUI
import CoreBluetooth

struct ConnectionStatusCard: View {
    @EnvironmentObject var bluetoothService: BluetoothService
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: connectionStatusIcon)
                    .font(.title2)
                    .foregroundColor(connectionStatusColor)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connection")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(connectionStatusText)
                        .font(.subheadline)
                        .foregroundColor(connectionStatusColor)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                connectionStatusBadge
            }
            
            if bluetoothService.trainerConnectionStatus == .connected,
               let range = bluetoothService.resistanceRange {
                Divider()
                
                VStack(spacing: 8) {
                    Text("Trainer Capabilities")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    HStack {
                        Label("Range", systemImage: "slider.horizontal.below.rectangle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("\(range.min) - \(range.max)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                    }
                    
                    HStack {
                        Label("Increment", systemImage: "plus.minus")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("\(range.increment)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                    }
                }
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
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
    
    private var connectionStatusBadge: some View {
        Group {
            switch bluetoothService.trainerConnectionStatus {
            case .connected:
                Text("CONNECTED")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color("PrimaryGreen"))
                    .cornerRadius(6)
                
            case .connecting:
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("CONNECTING")
                        .font(.caption2)
                        .fontWeight(.bold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color("BrightOrange"))
                .cornerRadius(6)
                
            default:
                Text("DISCONNECTED")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color("SoftRed"))
                    .cornerRadius(6)
            }
        }
    }
}

// Legacy ConnectView for backwards compatibility (can be removed later)
struct ConnectView: View {
    var body: some View {
        NavigationView {
            VStack {
                Text("Connection features have moved to the Home tab")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                
                ConnectionStatusCard()
                    .padding()
                
                Spacer()
            }
            .navigationTitle("Connect")
            .background(Color(.systemGroupedBackground))
        }
    }
}

#Preview {
    ConnectView()
        .environmentObject(BluetoothService.shared)
}

