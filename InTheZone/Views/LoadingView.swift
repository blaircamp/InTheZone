import SwiftUI

struct LoadingView: View {
    @State private var isAnimating = false
    @State private var currentStep = 0
    
    private let loadingSteps = [
        "Initializing services...",
        "Setting up Bluetooth...",
        "Loading settings...",
        "Ready to connect!"
    ]
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color("PrimaryGreen").opacity(0.1),
                    Color("SecondaryGreen").opacity(0.05)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                // App Logo/Icon
                VStack(spacing: 16) {
                    Image(systemName: "bicycle")
                        .font(.system(size: 80, weight: .light))
                        .foregroundColor(Color("PrimaryGreen"))
                        .scaleEffect(isAnimating ? 1.1 : 1.0)
                        .animation(
                            Animation.easeInOut(duration: 1.5)
                                .repeatForever(autoreverses: true),
                            value: isAnimating
                        )
                    
                    Text("InTheZone")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("Bike Trainer")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
                
                // Loading Animation
                VStack(spacing: 24) {
                    // Progress dots
                    HStack(spacing: 8) {
                        ForEach(0..<4, id: \.self) { index in
                            Circle()
                                .fill(index <= currentStep ? Color("PrimaryGreen") : Color.gray.opacity(0.3))
                                .frame(width: 12, height: 12)
                                .scaleEffect(index == currentStep ? 1.2 : 1.0)
                                .animation(.easeInOut(duration: 0.3), value: currentStep)
                        }
                    }
                    
                    // Loading text
                    Text(currentStep < loadingSteps.count ? loadingSteps[currentStep] : "Ready!")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .animation(.easeInOut(duration: 0.3), value: currentStep)
                }
                
                Spacer()
                
                // Version info
                Text("Version 0.2.0")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 20)
            }
            .padding()
        }
        .onAppear {
            startAnimation()
        }
    }
    
    private func startAnimation() {
        isAnimating = true
        
        // Animate through loading steps
        Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { timer in
            if currentStep < loadingSteps.count - 1 {
                currentStep += 1
            } else {
                timer.invalidate()
            }
        }
    }
}

#Preview {
    LoadingView()
}