# iOS Live Activity (Dynamic Island + lock-screen trip tracker)

**Status: built and wired.** The `VoyplanTripActivity` widget-extension target
is in the Xcode project, embedded in the app, and signed with the free personal
team (P9386HP4WF) — so it installs and runs without a paid Apple Developer
account. It starts automatically when you begin driving navigation.

## How it works

- `lib/services/live_activity_service.dart` — Dart bridge (channel
  `com.travelapp.liveactivity`), called by `TripNotificationService` on every
  trip start/update/end.
- `ios/Runner/AppDelegate.swift` — routes the channel to `LiveActivityManager`.
- `ios/Runner/LiveActivityManager.swift` — starts/updates/ends the ActivityKit
  activity (app-side).
- `ios/VoyplanTripActivity/` — the widget extension:
  - `TripActivityAttributes.swift` — shared state (member of both targets).
  - `VoyplanTripActivityLiveActivity.swift` — the lock-screen card + Dynamic
    Island UI.
  - `VoyplanTripActivityBundle.swift` — the `@main` widget bundle.
- `ios/Runner/Info.plist` — `NSSupportsLiveActivities = true`.

## Requirements to see it

- iOS 16.1+ (Dynamic Island needs iPhone 14 Pro or newer; on other iPhones it
  still shows on the lock screen and in the notification stack).
- Live Activities enabled: Settings → Face ID & Passcode → Allow Live
  Activities, and Settings → Voyplan → Live Activities.

## Rebuilding

`flutter build ios --release` embeds and signs the extension automatically. If a
fresh machine ever fails to create the extension's provisioning profile, run
once: `xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration
Release -destination "generic/platform=iOS" -allowProvisioningUpdates build`,
then `flutter build ios` again.

## Recreating the target from scratch

If the target is ever lost, `scratchpad/add_widget_target.rb` (xcodeproj) rebuilds
it: creates the extension, adds the sources, embeds it **before** the Thin Binary
phase (avoids a build cycle), and sets a literal `CURRENT_PROJECT_VERSION` /
`MARKETING_VERSION` (an empty `CFBundleVersion` blocks install).
