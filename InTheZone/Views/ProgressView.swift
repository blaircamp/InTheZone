import SwiftUI

struct TrainingProgressView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @StateObject private var logger = SessionLogger.shared
    @State private var showingLogExport = false
    @State private var logFilesToExport: [URL] = []

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header Section
                    headerSection
                    
                    // Sessions List
                    sessionsSection
                    
                    Spacer(minLength: 20)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Progress")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: exportSessionData) {
                            Label("Export Session Data", systemImage: "square.and.arrow.up")
                        }
                        
                        if logger.isLoggingEnabled {
                            Button(action: exportDebugLogs) {
                                Label("Export Debug Logs", systemImage: "doc.text")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(Color("PrimaryGreen"))
                    }
                }
            }
            .sheet(isPresented: $showingLogExport) {
                ShareSheet(activityItems: logFilesToExport)
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title2)
                    .foregroundColor(Color("PrimaryGreen"))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Training Progress")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("\(sessionManager.savedSessions.count) sessions completed")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            if !sessionManager.savedSessions.isEmpty {
                // Quick Stats
                quickStatsSection
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    // MARK: - Quick Stats Section
    private var quickStatsSection: some View {
        HStack(spacing: 16) {
            statCard(
                title: "Total Work",
                value: String(format: "%.1f", sessionManager.savedSessions.reduce(0) { $0 + $1.totalWork }),
                unit: "kJ",
                color: Color("BrightOrange")
            )
            
            statCard(
                title: "Avg Power",
                value: String(format: "%.0f", sessionManager.savedSessions.reduce(0) { $0 + $1.averagePower } / Double(max(sessionManager.savedSessions.count, 1))),
                unit: "W",
                color: Color("SecondaryGreen")
            )
        }
    }
    
    private func statCard(title: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title2)
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
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Sessions Section
    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent Sessions")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .padding(.horizontal, 4)
            
            if sessionManager.savedSessions.isEmpty {
                emptyStateView
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(sessionManager.savedSessions.sorted(by: { $0.startTime > $1.startTime })) { session in
                        NavigationLink(destination: SessionDetailView(session: session)) {
                            sessionCard(session)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.run")
                .font(.system(size: 48))
                .foregroundColor(Color("PrimaryGreen"))
            
            VStack(spacing: 8) {
                Text("No Sessions Yet")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("Complete your first workout to see your progress here")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    // MARK: - Session Card
    private func sessionCard(_ session: TrainingSession) -> some View {
        HStack(spacing: 16) {
            // Date Column
            VStack(alignment: .leading, spacing: 4) {
                Text(session.startTime, style: .date)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(session.startTime, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Metrics Column
            HStack(spacing: 20) {
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("\(Int(session.averagePower))")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(Color("BrightOrange"))
                        Text("W")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text("Power")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(String(format: "%.1f", session.totalWork))
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(Color("SecondaryGreen"))
                        Text("kJ")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text("Work")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            // Arrow
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 1)
    }
    
    private func exportSessionData() {
        let csvData = sessionManager.exportAllSessionsAsCSV()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("training_sessions_\(ISO8601DateFormatter().string(from: Date())).csv")
        
        do {
            try csvData.write(to: tempURL, atomically: true, encoding: .utf8)
            logFilesToExport = [tempURL]
            showingLogExport = true
            
            logger.info("Session data exported", source: "TrainingProgressView", metadata: [
                "export_file": tempURL.lastPathComponent,
                "sessions_count": sessionManager.savedSessions.count
            ])
        } catch {
            logger.error("Failed to export session data", source: "TrainingProgressView", metadata: [
                "error": error.localizedDescription
            ])
        }
    }
    
    private func exportDebugLogs() {
        let logFiles = logger.getAllLogFiles()
        
        if logFiles.isEmpty {
            logger.warning("No debug log files found for export", source: "TrainingProgressView")
            return
        }
        
        logFilesToExport = logFiles
        showingLogExport = true
        
        logger.info("Debug logs exported", source: "TrainingProgressView", metadata: [
            "log_files_count": logFiles.count,
            "log_files": logFiles.map { $0.lastPathComponent }
        ])
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    TrainingProgressView()
        .environmentObject(SessionManager())
}

