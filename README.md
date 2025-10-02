# InTheZone - A Simple and Effective Bike Trainer App

## Overview

InTheZone is a streamlined iOS and Apple Watch application designed for a straightforward indoor cycling experience. It connects to FTMS (Fitness Machine Service) compatible smart trainers via Bluetooth, allowing you to manually control resistance, monitor your performance, and record your workouts with ease.

## Key Features

### Manual Resistance Control
- **Direct Control**: Easily adjust your trainer's resistance level manually during your workout.
- **Configurable Steps**: Set custom resistance step sizes for fine-tuned or large adjustments.

### 📱 iOS App Features
- **Real-time Metrics Dashboard**: View power, cadence, speed, and heart rate in real-time.
- **Live Performance Charts**: Visualize your workout metrics as they happen.
- **Session Recording**: Track and save all workout data for later analysis.
- **Progress Tracking**: Review past sessions, analyze trends, and export data.

### ⌚ Apple Watch Integration
- **Heart Rate Monitoring**: Direct heart rate measurement from Apple Watch.
- **Remote Control**: Start/stop sessions from your wrist.
- **Haptic Feedback**: Feel resistance changes through wrist taps.
- **Synchronized Timers**: Session duration perfectly synced between devices.
- **Live Metrics Display**: See current HR and resistance level on watch face.

### 🎮 Zwift Click Support
- **Wireless Control**: Use Zwift Click buttons to adjust resistance.
- **Auto-Discovery**: Automatically connects to nearby Zwift Click devices.

## Technical Architecture

### Core Technologies
- **SwiftUI**: Modern declarative UI framework for both iOS and watchOS.
- **Core Bluetooth**: Direct communication with FTMS trainers.
- **WatchConnectivity**: Real-time data sync between iPhone and Apple Watch.
- **Combine Framework**: Reactive data flow and event handling.

### Core Components

- **`BluetoothService`**: Manages all communication with the FTMS trainer.
- **`SessionManager`**: Handles the recording and storage of workout sessions.
- **`ResistanceStateManager`**: Manages the resistance state and prevents command flooding.
- **`WatchCommunicationManager`**: Synchronizes data and commands with the Apple Watch.

### Communication Protocols

#### FTMS (Fitness Machine Service)
- **Indoor Bike Data Characteristic** (0x2AD2): Receives speed, cadence, power, resistance.
- **Fitness Machine Control Point** (0x2AD9): Sends resistance commands.
- **Supported Resistance Range** (0x2AD6): Queries trainer capabilities.

#### Watch Communication
- Real-time heart rate streaming.
- Bidirectional session control.
- Resistance change notifications.
- Session timer synchronization.

## User Interface

### iOS App Screens

#### Home View
- Quick access to all major features.
- Connection status indicators.
- Session quick-start button.

#### Workout View
- Live metrics display (grid layout).
- Real-time performance chart.
- Session control (start/stop/save).
- Manual resistance control.

#### Progress View
- Historical session list.
- Performance statistics.
- Data export options.
- Debug log access (when enabled).

#### Settings View
- Heart rate source selection.
- Resistance control settings.
- Watch app preferences.
- Debug logging toggle.

### Apple Watch App
- Minimalist design for at-a-glance metrics.
- Large, readable heart rate display.
- Session duration timer.
- Start/stop controls.
- Connection status indicator.

## Setup and Configuration

### Requirements
- iOS 15.0 or later
- watchOS 8.0 or later
- FTMS-compatible smart trainer
- iPhone with Bluetooth LE support
- Apple Watch (optional but recommended)

### Initial Setup
1. Install the app on iPhone and Apple Watch.
2. Grant Bluetooth permissions.
3. Grant Health app permissions (for heart rate).
4. Connect to your smart trainer.
5. Choose your heart rate source in Settings.

## Data Storage and Privacy

### Local Storage
- All workout data stored locally on device.
- No cloud sync or external servers.
- Export data remains under user control.

### Data Collected
- Workout metrics (power, cadence, HR, speed).
- Resistance changes and timestamps.
- Session durations and dates.
- No personal information beyond Health data.

### Debug Logging
- Optional debug logs for troubleshooting.
- Stored temporarily (auto-cleanup after 7 days).
- Can be exported for support purposes.
- No automatic transmission.

## Troubleshooting

### Common Issues

#### Trainer Won't Connect
- Ensure Bluetooth is enabled.
- Check trainer is powered on.
- Try power cycling the trainer.
- Verify no other apps are connected.

#### Heart Rate Not Showing
- Check Apple Watch is worn properly.
- Verify Watch app is running.
- Try switching HR source in Settings.
- Ensure Health permissions granted.

#### Resistance Not Changing
- Verify your trainer supports FTMS control.
- Ensure you're in a training session.

## Development

### Project Structure
```
InTheZone/
├── Services/
│   ├── BluetoothService.swift         # Main trainer communication
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
- **MVVM Architecture**: Clear separation of concerns.
- **Reactive Programming**: Combine for data flow.
- **Dependency Injection**: Via environment objects.
- **State Management**: SwiftUI @State and @Published.

### Testing Approach
- Unit tests for core logic.
- Integration tests for Bluetooth communication.
- UI tests for critical user flows.
- Manual testing with real trainers.

## Future Enhancements

### Planned Features
- **Workout Programs**: Pre-defined interval workouts.
- **Power-Based Control**: An alternative to manual resistance control.
- **Apple Health Integration**: Sync workouts to the Health app.
- **Social Features**: Share workouts with friends.
- **Advanced Analytics**: Detailed performance metrics.
- **Voice Feedback**: Audio cues for workout events.

## Contributing

This is currently a private project, but contributions and feedback are welcome. Please contact the developer for more information.

## License

Copyright © 2025 Blair Campbell. All rights reserved.

## Acknowledgments

- Thanks to the Bluetooth SIG for the FTMS specification.
- Inspired by TrainerRoad, Zwift, and other indoor cycling platforms.
- Built with Apple's excellent development tools and frameworks.

---

*InTheZone - Your Essential Indoor Cycling Companion* 🚴‍♂️💪