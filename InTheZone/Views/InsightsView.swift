import SwiftUI

struct InsightsView: View {
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Image(systemName: "brain.head.profile").font(.system(size: 48)).foregroundColor(.purple)
                Text("Smart Insights")
                    .font(.title2).bold()
                Text("Connect your Apple Watch and complete a few workouts to see personalized insights here.")
                    .font(.body).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Insights")
        }
    }
}

