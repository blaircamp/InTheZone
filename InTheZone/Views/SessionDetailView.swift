import SwiftUI

struct SessionDetailView: View {
    let session: TrainingSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            List {
                Section(header: Text("Summary")) {
                    HStack { Text("Date"); Spacer(); Text(session.startTime, style: .date) }
                    HStack { Text("Duration"); Spacer(); Text(formatDuration(session.duration)) }
                    HStack { Text("Avg Power"); Spacer(); Text("\(Int(session.averagePower)) W") }
                    HStack { Text("Max Power"); Spacer(); Text("\(Int(session.maxPower)) W") }
                    HStack { Text("Avg HR"); Spacer(); Text("\(Int(session.averageHeartRate)) bpm") }
                }
                if !session.resistanceChanges.isEmpty {
                    Section(header: Text("Resistance Changes")) {
                        ForEach(session.resistanceChanges) { change in
                            HStack {
                                Text(change.timestamp, style: .time)
                                Spacer()
                                Text("\(Int(change.oldResistance)) → \(Int(change.newResistance))")
                                Text(change.reason.rawValue).foregroundColor(change.reason.color).font(.caption)
                            }
                        }
                    }
                }
                Section(header: Text("Export")) {
                    Button("Export CSV") { exportCSV() }
                }
            }
        }
        .navigationTitle("Session")
        .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } } }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let h = Int(duration)/3600
        let m = (Int(duration)%3600)/60
        let s = Int(duration)%60
        return h>0 ? String(format: "%d:%02d:%02d", h,m,s) : String(format: "%d:%02d", m,s)
    }

    private func exportCSV() {
        let export = exportCSVString()
        let activityVC = UIActivityViewController(activityItems: [export], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene, let window = scene.windows.first {
            window.rootViewController?.present(activityVC, animated: true)
        }
    }

    private func exportCSVString() -> String {
        var csv = "Timestamp,Heart Rate,Power,Cadence,Resistance\n"
        for m in session.metrics {
            let ts = ISO8601DateFormatter().string(from: m.timestamp)
            let cadenceFormatted = m.cadence.map { formatValue($0) } ?? "0"
            csv += "\(ts),\(m.heartRate ?? 0),\(m.power),\(cadenceFormatted),\(m.resistance)\n"
        }
        return csv
    }
    
    private func formatValue(_ value: Double) -> String {
        // If the value is a whole number, show no decimals
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        }
        // Otherwise show up to 2 decimal places
        return String(format: "%.2f", value)
    }
}

