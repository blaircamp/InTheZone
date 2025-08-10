# InTheZone - Smart Indoor Cycling Trainer Control System

## Overview

InTheZone is an advanced iOS and Apple Watch application that transforms your indoor cycling experience by providing intelligent, automatic resistance control based on heart rate zones. The app connects to FTMS (Fitness Machine Service) compatible smart trainers via Bluetooth and uses sophisticated control algorithms to keep you training in your optimal heart rate zone.

## Key Features

### 🎯 Intelligent Auto-Resistance Control
- **Predictive Kalman Filtering**: Uses a 2D Kalman filter to predict heart rate trends and make proactive resistance adjustments
- **Machine Learning Optimization**: The system learns from your responses to resistance changes and adapts its control strategy over time
- **Cadence Protection**: Prevents resistance from becoming too high when cadence drops below threshold, ensuring sustainable workouts
- **Zone-Based Training**: Automatically adjusts resistance to maintain your heart rate within your target training zone

### 📱 iOS App Features
- **Real-time Metrics Dashboard**: View power, cadence, speed, and heart rate in real-time
- **Live Performance Charts**: Visualize your workout metrics as they happen
- **Session Recording**: Track and save all workout data for later analysis
- **Progress Tracking**: Review past sessions, analyze trends, and export data
- **Customizable Settings**: Configure heart rate zones, resistance step sizes, and cadence thresholds

### ⌚ Apple Watch Integration
- **Heart Rate Monitoring**: Direct heart rate measurement from Apple Watch
- **Remote Control**: Start/stop sessions from your wrist
- **Haptic Feedback**: Feel resistance changes through wrist taps
- **Synchronized Timers**: Session duration perfectly synced between devices
- **Live Metrics Display**: See current HR and resistance level on watch face

### 🎮 Zwift Click Support
- **Wireless Control**: Use Zwift Click buttons to adjust resistance
- **Configurable Steps**: Set custom resistance step sizes for button presses
- **Auto-Discovery**: Automatically connects to nearby Zwift Click devices

## Technical Architecture

### Core Technologies
- **SwiftUI**: Modern declarative UI framework for both iOS and watchOS
- **Core Bluetooth**: Direct communication with FTMS trainers
- **WatchConnectivity**: Real-time data sync between iPhone and Apple Watch
- **Combine Framework**: Reactive data flow and event handling
- **SIMD**: High-performance matrix operations for Kalman filtering

### Control System Components

#### 1. Kalman Heart Rate Filter (`KalmanHR2DFilter`)
- 2-state constant-velocity model tracking HR and HR velocity (rate of change)
- Provides smooth, predictive heart rate estimates
- Reduces noise from sensor measurements
- Predicts future heart rate trends for proactive control

#### 2. Heart Rate Zone Controller (`HeartRateZoneController`)
- Implements predictive control with configurable horizon (default 7 seconds)
- Features hysteresis to prevent oscillation
- Adaptive step sizing based on error magnitude
- Machine learning system that improves over time

#### 3. Resistance State Manager (`ResistanceStateManager`)
- Centralized resistance control with debouncing
- Prevents command flooding to trainer
- Maintains display state separate from actual trainer state
- Handles Zwift Click integration

#### 4. Session Management
- Comprehensive workout data recording
- Automatic metric smoothing and validation
- Export capabilities (CSV format)
- Integration with Apple Health (planned)

### Communication Protocols

#### FTMS (Fitness Machine Service)
- **Indoor Bike Data Characteristic** (0x2AD2): Receives speed, cadence, power, resistance
- **Fitness Machine Control Point** (0x2AD9): Sends resistance commands
- **Supported Resistance Range** (0x2AD6): Queries trainer capabilities

#### Watch Communication
- Real-time heart rate streaming
- Bidirectional session control
- Resistance change notifications
- Session timer synchronization

## Algorithm Details

### Adaptive Resistance Control

The system uses a multi-layered approach to resistance control:

1. **Primary Loop**: Kalman-filtered HR → Zone Controller → Resistance Command
2. **Cadence Override**: Reduces resistance if cadence drops below threshold
3. **Learning System**: Tracks effectiveness of resistance changes and adapts

#### Control Parameters
- **Prediction Horizon**: 7 seconds ahead
- **Deadband**: ±2 BPM to prevent chatter
- **Update Interval**: Minimum 5 seconds between changes
- **Max Step Size**: 3 resistance levels per adjustment

### Cadence-Based Protection

The system monitors cadence to ensure workouts remain sustainable:
- **Minimum Threshold**: User-configurable (40-100 RPM)
- **Override Logic**: Reduces resistance when cadence too low
- **Smart Increases**: Won't increase resistance if already struggling
- **Zone Priority**: Balances HR goals with cadence maintenance

## User Interface

### iOS App Screens

#### Home View
- Quick access to all major features
- Connection status indicators
- Session quick-start button

#### Workout View
- Live metrics display (grid layout)
- Real-time performance chart
- Session control (start/stop/save)
- Resistance control (manual or auto)
- Cadence protection indicator

#### Progress View
- Historical session list
- Performance statistics
- Data export options
- Debug log access (when enabled)

#### Settings View
- Heart rate source selection
- Target zone configuration
- Resistance control settings
- Cadence thresholds
- Watch app preferences
- Debug logging toggle

### Apple Watch App
- Minimalist design for at-a-glance metrics
- Large, readable heart rate display
- Session duration timer
- Start/stop controls
- Connection status indicator

## Setup and Configuration

### Requirements
- iOS 15.0 or later
- watchOS 8.0 or later
- FTMS-compatible smart trainer
- iPhone with Bluetooth LE support
- Apple Watch (optional but recommended)

### Initial Setup
1. Install the app on iPhone and Apple Watch
2. Grant Bluetooth permissions
3. Grant Health app permissions (for heart rate)
4. Connect to your smart trainer
5. Configure heart rate zones in Settings
6. Set cadence thresholds if desired
7. Choose heart rate source (Watch/Trainer/Auto)

### Recommended Settings
- **Heart Rate Zone**: Set to your aerobic/tempo zone
- **Minimum Cadence**: 60-70 RPM for beginners, 70-80 for experienced
- **Resistance Steps**: 1 for fine control, 5 for quick changes
- **Auto Control**: Enable for zone-based training

## Data Storage and Privacy

### Local Storage
- All workout data stored locally on device
- No cloud sync or external servers
- Export data remains under user control

### Data Collected
- Workout metrics (power, cadence, HR, speed)
- Resistance changes and timestamps
- Session durations and dates
- No personal information beyond Health data

### Debug Logging
- Optional debug logs for troubleshooting
- Stored temporarily (auto-cleanup after 7 days)
- Can be exported for support purposes
- No automatic transmission

## Troubleshooting

### Common Issues

#### Trainer Won't Connect
- Ensure Bluetooth is enabled
- Check trainer is powered on
- Try power cycling the trainer
- Verify no other apps are connected

#### Heart Rate Not Showing
- Check Apple Watch is worn properly
- Verify Watch app is running
- Try switching HR source in Settings
- Ensure Health permissions granted

#### Resistance Not Changing
- Verify trainer supports FTMS control
- Check Auto Control is enabled
- Ensure you're in a training session
- Try manual resistance control first

#### Cadence Protection Too Aggressive
- Increase minimum cadence threshold
- Disable cadence control temporarily
- Adjust target heart rate zone

## Development

### Project Structure
```
InTheZone/
├── Services/
│   ├── BluetoothService.swift         # Main trainer communication
│   ├── KalmanHR2DFilter.swift         # Heart rate filtering
│   ├── HeartRateZoneController.swift  # Resistance control logic
│   ├── SessionManager.swift           # Workout recording
│   └── WatchCommunicationManager.swift # iPhone ↔ Watch sync
├── Views/
│   ├── HomeView.swift                 # Main navigation
│   ├── WorkoutView.swift              # Live workout screen
│   ├── ProgressView.swift             # Historical data
│   └── SettingsView.swift             # Configuration
└── InTheZoneWatch Watch App/
    ├── ContentView.swift              # Watch UI
    └── WatchWCManager.swift           # Watch communication
```

### Key Design Patterns
- **MVVM Architecture**: Clear separation of concerns
- **Reactive Programming**: Combine for data flow
- **Dependency Injection**: Via environment objects
- **State Management**: SwiftUI @State and @Published

### Testing Approach
- Unit tests for control algorithms
- Integration tests for Bluetooth communication
- UI tests for critical user flows
- Manual testing with real trainers

## Future Enhancements

### Planned Features
- **Workout Programs**: Pre-defined interval workouts
- **Power-Based Control**: Alternative to HR-based control
- **Apple Health Integration**: Sync workouts to Health app
- **Social Features**: Share workouts with friends
- **Advanced Analytics**: Detailed performance metrics
- **Voice Feedback**: Audio cues for zone changes

### Algorithm Improvements
- **Multi-zone Support**: Different zones for intervals
- **Recovery Detection**: Automatic cool-down periods
- **Fatigue Modeling**: Adjust targets based on accumulated fatigue
- **Weather Integration**: Adjust for temperature/humidity

## Contributing

This is currently a private project, but contributions and feedback are welcome. Please contact the developer for more information.

## License

Copyright © 2025 Blair Campbell. All rights reserved.

## Acknowledgments

- Thanks to the Bluetooth SIG for the FTMS specification
- Inspired by TrainerRoad, Zwift, and other indoor cycling platforms
- Built with Apple's excellent development tools and frameworks

---

*InTheZone - Stay in your zone, maximize your gains* 🚴‍♂️💪