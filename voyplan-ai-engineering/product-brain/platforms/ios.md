# VoyPlan Platform — iOS Architecture

## 1. Project Topology
- Directory: `mobile/ios/`
- Target: `Runner.xcworkspace`
- Deployment Target: iOS 13.0+

## 2. In-Vehicle Connected Apple CarPlay
- `AppDelegate.swift`: Sets up Flutter platform channel handlers.
- `CarPlayVoiceGuidance.swift`: Native AVFoundation speech synthesis for road maneuvers and safety advisories.
