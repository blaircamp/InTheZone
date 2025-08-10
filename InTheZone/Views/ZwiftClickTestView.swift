import SwiftUI
import Combine

struct ZwiftClickTestView: View {
    @StateObject private var zwiftClickService = ZwiftClickService.shared
    @State private var buttonEvents: [String] = []
    @State private var resistanceLevel: Int = 50
    @State private var cancellable: AnyCancellable?
    @AppStorage("resistanceStepSize") private var resistanceStepSize: Int = 1
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Connection Status Card
                    connectionStatusCard
                    
                    // Simulated Resistance Display
                    simulatedResistanceCard
                    
                    // Button Events Log
                    eventLogCard
                    
                    // Control Buttons
                    controlButtonsCard
                    
                    Spacer(minLength: 20)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Zwift Click Test")
            .onAppear {
                setupButtonListener()
            }
            .onDisappear {
                cancellable?.cancel()
            }
        }
    }
    
    // MARK: - Connection Status
    private var connectionStatusCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: zwiftClickService.isConnected ? "gamecontroller.fill" : "gamecontroller")
                    .font(.title2)
                    .foregroundColor(zwiftClickService.isConnected ? Color("PrimaryGreen") : .secondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Zwift Click Status")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(zwiftClickService.isConnected ? "Connected" : "Not Connected")
                        .font(.subheadline)
                        .foregroundColor(zwiftClickService.isConnected ? Color("PrimaryGreen") : .secondary)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                if zwiftClickService.isConnected {
                    if let battery = zwiftClickService.batteryLevel {
                        HStack(spacing: 4) {
                            Image(systemName: batteryIcon(for: battery))
                                .font(.caption)
                            Text("\(battery)%")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(batteryColor(for: battery))
                    }
                }
            }
            
            if let device = zwiftClickService.discoveredDevice, !zwiftClickService.isConnected {
                Divider()
                
                Button(action: {
                    zwiftClickService.connect(to: device)
                }) {
                    HStack {
                        Image(systemName: "link.circle.fill")
                        Text("Connect to \(device.name ?? "Zwift Click")")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color("BrightOrange"))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
            } else if !zwiftClickService.isConnected {
                Divider()
                
                Button(action: {
                    if zwiftClickService.isScanning {
                        zwiftClickService.stopScan()
                    } else {
                        zwiftClickService.startScan()
                    }
                }) {
                    HStack {
                        if zwiftClickService.isScanning {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                        } else {
                            Image(systemName: "magnifyingglass")
                        }
                        Text(zwiftClickService.isScanning ? "Scanning..." : "Scan for Zwift Click")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color("PrimaryGreen"))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    // MARK: - Simulated Resistance
    private var simulatedResistanceCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "dial.medium.fill")
                    .font(.title2)
                    .foregroundColor(Color("BrightOrange"))
                
                Text("Simulated Resistance")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            
            VStack(spacing: 12) {
                // Large resistance display
                Text("\(resistanceLevel)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(Color("PrimaryGreen"))
                
                Text("Resistance Level")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    Text("Range: 0 - 100")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text("Step: \(resistanceStepSize)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fontWeight(.medium)
                }
                
                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemGray5))
                            .frame(height: 8)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color("PrimaryGreen"), Color("SecondaryGreen")]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * CGFloat(resistanceLevel) / 100.0, height: 8)
                    }
                }
                .frame(height: 8)
                .padding(.top, 8)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    // MARK: - Event Log
    private var eventLogCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "list.bullet.rectangle")
                    .font(.title2)
                    .foregroundColor(Color("BrightBlue"))
                
                Text("Button Events")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if !buttonEvents.isEmpty {
                    Button("Clear") {
                        buttonEvents.removeAll()
                    }
                    .font(.caption)
                    .foregroundColor(Color("SoftRed"))
                }
            }
            
            if buttonEvents.isEmpty {
                Text("No button events yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(buttonEvents.enumerated().reversed()), id: \.offset) { index, event in
                        HStack {
                            Text(event)
                                .font(.caption)
                                .foregroundColor(.primary)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }
                }
                .frame(maxHeight: 200)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    // MARK: - Control Buttons
    private var controlButtonsCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "hand.tap.fill")
                    .font(.title2)
                    .foregroundColor(Color("SecondaryGreen"))
                
                Text("Test Controls")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            
            if zwiftClickService.isConnected {
                VStack(spacing: 12) {
                    Button(action: {
                        zwiftClickService.sendHandshakeManually()
                        addEvent("Sent manual handshake")
                    }) {
                        HStack {
                            Image(systemName: "hand.wave.fill")
                            Text("Send Handshake")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color("BrightBlue"))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    
                    Button(action: {
                        zwiftClickService.testReadCharacteristics()
                        addEvent("Testing read from characteristics")
                    }) {
                        HStack {
                            Image(systemName: "doc.text.magnifyingglass")
                            Text("Test Read")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color("BrightOrange"))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    
                    // Alternative initialization attempts
                    HStack(spacing: 8) {
                        Button(action: {
                            zwiftClickService.sendAlternativeStart()
                            addEvent("Sent RideOn + RequestStart")
                        }) {
                            Text("Alt Start")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.purple)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        
                        Button(action: {
                            zwiftClickService.sendSimpleStart()
                            addEvent("Sent simple start byte")
                        }) {
                            Text("Simple Start")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.indigo)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        
                        Button(action: {
                            zwiftClickService.acknowledgeHandshake()
                            addEvent("Sent ACK for 0x03")
                        }) {
                            Text("Send ACK")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                    
                    Button(action: {
                        // Disconnect and reconnect
                        zwiftClickService.disconnect()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            zwiftClickService.startScan()
                        }
                        addEvent("Reconnecting...")
                    }) {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Reconnect")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color("SoftRed"))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                }
                
                Text("Press the Plus/Minus buttons on your Zwift Click to test resistance changes")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            } else {
                Text("Connect a Zwift Click to test button events")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 20)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    // MARK: - Helper Functions
    private func setupButtonListener() {
        cancellable = zwiftClickService.buttonEventPublisher
            .sink { event in
                let buttonName = event.button == .plus ? "Plus (+)" : "Minus (-)"
                let timestamp = DateFormatter.localizedString(from: event.timestamp, dateStyle: .none, timeStyle: .medium)
                
                // Simulate resistance change
                let change = event.button == .plus ? resistanceStepSize : -resistanceStepSize
                let newLevel = max(0, min(100, resistanceLevel + change))
                resistanceLevel = newLevel
                
                let eventText = "\(timestamp): \(buttonName) pressed - Resistance: \(newLevel) (\(change >= 0 ? "+" : "")\(change))"
                addEvent(eventText)
            }
    }
    
    private func addEvent(_ event: String) {
        buttonEvents.append(event)
        
        // Keep only last 10 events
        if buttonEvents.count > 10 {
            buttonEvents.removeFirst()
        }
    }
    
    private func batteryIcon(for level: Int) -> String {
        switch level {
        case 0...20: return "battery.0"
        case 21...50: return "battery.25"
        case 51...75: return "battery.50"
        default: return "battery.100"
        }
    }
    
    private func batteryColor(for level: Int) -> Color {
        switch level {
        case 0...20: return Color("SoftRed")
        case 21...50: return Color("BrightOrange")
        default: return Color("PrimaryGreen")
        }
    }
}

#Preview {
    ZwiftClickTestView()
}