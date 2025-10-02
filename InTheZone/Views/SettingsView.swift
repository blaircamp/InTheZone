import SwiftUI

struct SettingsView: View {
    @AppStorage("heartRateSource") private var heartRateSourceRaw: String = HeartRateSource.auto.rawValue
    @AppStorage("useWatchAppForSessions") private var useWatchAppForSessions: Bool = false
    @AppStorage("resistanceStepSize") private var resistanceStepSize: Int = 1
    @AppStorage("minCadenceThreshold") private var minCadenceThreshold: Double = 60.0
    @AppStorage("targetCadenceRange") private var targetCadenceRange: String = "70-90"
    @AppStorage("useCadenceControl") private var useCadenceControl: Bool = true
    @StateObject private var logger = SessionLogger.shared

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Heart Rate Source Section
                    heartRateSourceSection
                    
                    // Resistance Control Settings Section
                    resistanceControlSection
                    
                    // Watch App Integration Section
                    watchAppIntegrationSection
                    
                    // Debug Logging Section
                    debugLoggingSection
                    
                    // About Section
                    aboutSection
                    
                    // Developer Section (for testing)
                    developerSection
                    
                    Spacer(minLength: 20)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Settings")
        }
    }
    
    // MARK: - Heart Rate Source Section
    private var heartRateSourceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "heart.fill")
                    .font(.title2)
                    .foregroundColor(Color("SoftRed"))
                
                Text("Heart Rate Source")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            
            VStack(spacing: 12) {
                Picker("Source", selection: $heartRateSourceRaw) {
                    Label("Apple Watch", systemImage: "applewatch")
                        .tag(HeartRateSource.watch.rawValue)
                    Label("Trainer Sensor", systemImage: "bicycle")
                        .tag(HeartRateSource.trainer.rawValue)
                    Label("Auto (Watch if available)", systemImage: "brain.head.profile")
                        .tag(HeartRateSource.auto.rawValue)
                }
                .pickerStyle(.menu)
                .tint(Color("PrimaryGreen"))
                
                Text("Choose where to read heart rate data from during workouts")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    // MARK: - Resistance Control Settings Section
    private var resistanceControlSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "dial.medium.fill")
                    .font(.title2)
                    .foregroundColor(Color("BrightOrange"))
                
                Text("Resistance Control")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            
            VStack(spacing: 16) {
                // Resistance Step Size Setting
                VStack(alignment: .leading, spacing: 12) {
                    Text("Resistance Step Size")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    HStack {
                        Text("Steps per click:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        HStack(spacing: 16) {
                            Button(action: {
                                let newValue = max(TrainingConstants.Resistance.minStepSize, resistanceStepSize - 1)
                                resistanceStepSize = newValue
                            }) {
                                Image(systemName: "minus.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(Color("SoftRed"))
                            }
                            .disabled(resistanceStepSize <= TrainingConstants.Resistance.minStepSize)
                            
                            Text("\(resistanceStepSize)")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(Color("PrimaryGreen"))
                                .frame(minWidth: 40)
                            
                            Button(action: {
                                let newValue = min(TrainingConstants.Resistance.maxStepSize, resistanceStepSize + 1)
                                resistanceStepSize = newValue
                            }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(Color("PrimaryGreen"))
                            }
                            .disabled(resistanceStepSize >= TrainingConstants.Resistance.maxStepSize)
                        }
                    }
                    
                    Text("Each button press or Zwift Click action will change resistance by this many steps")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
                .background(Color("BrightOrange").opacity(0.1))
                .cornerRadius(8)
                
                // Quick presets
                HStack(spacing: 12) {
                    ForEach([1, 5, 10, 25], id: \.self) { preset in
                        Button(action: {
                            resistanceStepSize = preset
                        }) {
                            Text("\(preset)")
                                .font(.caption)
                                .fontWeight(resistanceStepSize == preset ? .bold : .medium)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(resistanceStepSize == preset ? Color("PrimaryGreen") : Color(.systemGray5))
                                .foregroundColor(resistanceStepSize == preset ? .white : .primary)
                                .cornerRadius(6)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                
                Text("Quick presets for common step sizes")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    // MARK: - Watch App Integration Section
    private var watchAppIntegrationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "applewatch")
                    .font(.title2)
                    .foregroundColor(Color("PrimaryGreen"))
                
                Text("Watch App Integration")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            
            VStack(spacing: 16) {
                Toggle("Use Watch for Sessions", isOn: $useWatchAppForSessions)
                    .tint(Color("PrimaryGreen"))
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("When enabled, starting a session will:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        bulletPoint("Launch the Watch app automatically")
                        bulletPoint("Monitor heart rate from Apple Watch")
                        bulletPoint("Provide haptic feedback for resistance changes")
                    }
                    .padding(.leading, 8)
                }
                .padding()
                .background(Color("PrimaryGreen").opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.caption)
                .foregroundColor(Color("PrimaryGreen"))
                .fontWeight(.bold)
            
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    // MARK: - Debug Logging Section
    private var debugLoggingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "doc.text.fill")
                    .font(.title2)
                    .foregroundColor(Color("BrightBlue"))
                
                Text("Debug Logging")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            
            VStack(spacing: 16) {
                Toggle("Enable Debug Logs", isOn: $logger.isLoggingEnabled)
                    .tint(Color("PrimaryGreen"))
                    .onChange(of: logger.isLoggingEnabled) { _, enabled in
                        if enabled {
                            logger.info("Debug logging enabled from settings", source: "SettingsView")
                        } else {
                            logger.info("Debug logging disabled from settings", source: "SettingsView")
                        }
                    }
                
                if logger.isLoggingEnabled {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Log Level")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        Picker("Log Level", selection: $logger.minimumLogLevel) {
                            Label("Debug", systemImage: "ladybug")
                                .tag(LogLevel.debug)
                            Label("Info", systemImage: "info.circle")
                                .tag(LogLevel.info)
                            Label("Warning", systemImage: "exclamationmark.triangle")
                                .tag(LogLevel.warning)
                            Label("Error", systemImage: "exclamationmark.circle")
                                .tag(LogLevel.error)
                        }
                        .pickerStyle(.menu)
                        .tint(Color("PrimaryGreen"))
                    }
                    .padding()
                    .background(Color("BrightBlue").opacity(0.1))
                    .cornerRadius(8)
                }
                
                Text("Debug logs capture detailed system information during training sessions and are stored locally on your device.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    // MARK: - About Section
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .font(.title2)
                    .foregroundColor(Color("SecondaryGreen"))
                
                Text("About")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            
            VStack(spacing: 12) {
                HStack {
                    Text("App")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text("InTheZone")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fontWeight(.medium)
                }
                
                Divider()
                
                HStack {
                    Text("Version")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text("0.2.0")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fontWeight(.medium)
                }
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    // MARK: - Developer Section
    private var developerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "hammer.fill")
                    .font(.title2)
                    .foregroundColor(.purple)
                
                Text("Developer Tools")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            
            NavigationLink(destination: ZwiftClickTestView()) {
                HStack {
                    Image(systemName: "gamecontroller.fill")
                        .font(.title3)
                        .foregroundColor(Color("BrightOrange"))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Zwift Click Test")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        Text("Test Zwift Click without a trainer")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

#Preview {
    SettingsView()
}

