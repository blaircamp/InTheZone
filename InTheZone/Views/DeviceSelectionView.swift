import SwiftUI
import CoreBluetooth

struct DeviceSelectionView: View {
    @EnvironmentObject var bluetoothService: BluetoothService
    @Environment(\.dismiss) private var dismiss
    @State private var hasStartedScan = false
    @StateObject private var zwiftClickService = ZwiftClickService.shared
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                headerSection
                
                // Device List
                deviceListSection
                
                Spacer()
            }
            .navigationTitle("Connect Device")
            .navigationBarTitleDisplayMode(.large)
            .navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        bluetoothService.stopScan()
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if bluetoothService.isScanning || zwiftClickService.isScanning {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Button("Scan") {
                            bluetoothService.startScan()
                            zwiftClickService.startScan()
                        }
                        .disabled(!bluetoothService.isBluetoothReady)
                    }
                }
            }
            .onAppear {
                if bluetoothService.isBluetoothReady && !hasStartedScan {
                    bluetoothService.startScan()
                    zwiftClickService.startScan()
                    hasStartedScan = true
                }
            }
            .onDisappear {
                bluetoothService.stopScan()
                zwiftClickService.stopScan()
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 48))
                .foregroundColor(Color("PrimaryGreen"))
            
            VStack(spacing: 8) {
                Text("Discover Devices")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Make sure your bike trainer is turned on and in pairing mode")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Scanning Status
            if bluetoothService.isScanning || zwiftClickService.isScanning {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Scanning for devices...")
                        .font(.caption)
                        .foregroundColor(Color("PrimaryGreen"))
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color("PrimaryGreen").opacity(0.1))
                .cornerRadius(8)
            } else if !bluetoothService.isBluetoothReady {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("Bluetooth not available")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(Color("SoftRed"))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color("SoftRed").opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }
    
    // MARK: - Device List Section
    private var deviceListSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            let hasDevices = !bluetoothService.discoveredPeripherals.isEmpty || zwiftClickService.discoveredDevice != nil
            
            if hasDevices {
                Text("Available Devices")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
            
            if !hasDevices {
                emptyStateView
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        // Show trainers
                        ForEach(bluetoothService.discoveredPeripherals, id: \.identifier) { peripheral in
                            deviceRow(peripheral, isTrainer: true)
                        }
                        
                        // Show Zwift Click if discovered
                        if let zwiftClick = zwiftClickService.discoveredDevice {
                            deviceRow(zwiftClick, isTrainer: false)
                        }
                    }
                    .padding()
                }
            }
        }
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text(bluetoothService.isScanning ? "Looking for devices..." : "No devices found")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                if !bluetoothService.isScanning {
                    Text("Tap 'Scan' to search for nearby bike trainers")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            if !bluetoothService.isScanning && !zwiftClickService.isScanning && bluetoothService.isBluetoothReady {
                Button("Start Scanning") {
                    bluetoothService.startScan()
                    zwiftClickService.startScan()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color("PrimaryGreen"))
                .padding(.top, 8)
            }
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Device Row
    private func deviceRow(_ peripheral: CBPeripheral, isTrainer: Bool) -> some View {
        Button(action: {
            if isTrainer {
                bluetoothService.connect(to: peripheral)
                dismiss()
            } else {
                // Connect to Zwift Click
                zwiftClickService.connect(to: peripheral)
                dismiss()
            }
        }) {
            HStack(spacing: 16) {
                // Device Icon
                VStack {
                    Image(systemName: deviceIcon(for: peripheral, isTrainer: isTrainer))
                        .font(.title2)
                        .foregroundColor(isTrainer ? Color("PrimaryGreen") : Color("BrightOrange"))
                    
                    Spacer()
                }
                
                // Device Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(peripheral.name ?? "Unknown Device")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                    
                    Text(isTrainer ? "Bike Trainer" : "Zwift Click Controller")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if !isTrainer {
                        Text("Resistance control accessory")
                            .font(.caption)
                            .foregroundColor(Color("BrightOrange"))
                            .fontWeight(.medium)
                    }
                    
                    Text("ID: \(peripheral.identifier.uuidString.prefix(8))...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Connection status or Connect Arrow
                if !isTrainer && zwiftClickService.isConnected {
                    Text("CONNECTED")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color("BrightOrange"))
                        .cornerRadius(6)
                } else {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title3)
                        .foregroundColor(isTrainer ? Color("PrimaryGreen") : Color("BrightOrange"))
                }
            }
            .padding()
            .background(Color.white)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 1)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Helper Functions
    private func deviceIcon(for peripheral: CBPeripheral, isTrainer: Bool) -> String {
        let name = peripheral.name?.lowercased() ?? ""
        
        if !isTrainer || name.contains("zwift click") || name.contains("click") {
            return "gamecontroller.fill"
        } else if name.contains("trainer") || name.contains("bike") {
            return "bicycle"
        } else if name.contains("heart") || name.contains("hr") {
            return "heart.fill"
        } else {
            return "antenna.radiowaves.left.and.right"
        }
    }
}

#Preview {
    DeviceSelectionView()
        .environmentObject(BluetoothService.shared)
}