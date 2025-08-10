import SwiftUI

struct HeartRateZonePicker: View {
    @State private var lower: Double = TrainingConstants.HeartRateZones.lower
    @State private var upper: Double = TrainingConstants.HeartRateZones.upper

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Lower (bpm)")
                Spacer()
                Text("\(Int(lower))")
            }
            Slider(value: $lower, in: 60...200, step: 1) { _ in
                if lower > upper { upper = lower }
                TrainingConstants.HeartRateZones.set(lower: lower, upper: upper)
            }

            HStack {
                Text("Upper (bpm)")
                Spacer()
                Text("\(Int(upper))")
            }
            Slider(value: $upper, in: 60...220, step: 1) { _ in
                if upper < lower { lower = upper }
                TrainingConstants.HeartRateZones.set(lower: lower, upper: upper)
            }
            Text("Target: \(Int(lower))–\(Int(upper)) bpm").foregroundColor(.secondary).font(.footnote)
        }
        .onAppear {
            lower = TrainingConstants.HeartRateZones.lower
            upper = TrainingConstants.HeartRateZones.upper
        }
    }
}

