# Apple CarPlay integration

Scaffolding for the CarPlay navigation scene. **Not yet compiled** — integrate in
Xcode on a Mac with the full toolchain, and test in the CarPlay simulator.

## Prerequisites
- Apple Developer Program membership.
- **CarPlay entitlement approved** (`com.apple.developer.carplay-maps`) — see
  `../PHASE0_ACCOUNTS_ENTITLEMENT.md`. You can write/build the code before
  approval, but a device build/submission needs it.

## 1. Add the Swift file to the Runner target
- Put `CarPlaySceneDelegate.swift` in `mobile/ios/Runner/CarPlay/`.
- In Xcode, add it to the **Runner** target (checkbox in the file inspector) so
  it's compiled. (Adding a file to disk is not enough — it must be a build member.)

## 2. Expose the FlutterEngine to the scene
The default Flutter iOS app runs a `FlutterViewController` that owns the engine.
Make it reachable from the CarPlay scene. Simplest approach in `AppDelegate.swift`:

```swift
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterEngineProvider {
    lazy var flutterEngine: FlutterEngine? = {
        // Reuse the engine the root FlutterViewController created, or create a
        // shared one at launch and hand it to the root controller.
        return (window?.rootViewController as? FlutterViewController)?.engine
    }()
}
```
(For robustness, create a single `FlutterEngine` at launch, run it, register
plugins, and pass it to both the phone `FlutterViewController` and the CarPlay
scene — the shared-engine pattern.)

## 3. Merge Info.plist
Apply `Info.plist.additions.xml` into `mobile/ios/Runner/Info.plist`. This adds
the `CPTemplateApplicationScene` and points it at `CarPlaySceneDelegate`.
`$(PRODUCT_MODULE_NAME)` resolves to the Runner module (`Runner`).

## 4. Entitlement
After Apple approves, create `mobile/ios/Runner/Runner.entitlements`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>com.apple.developer.carplay-maps</key>
    <true/>
</dict></plist>
```
and set `CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements` in the Runner build
settings, with the entitlement enabled on the App ID in the developer portal.

## 5. Test
- iOS Simulator ▸ **I/O ▸ External Displays ▸ CarPlay** shows the CarPlay window.
- Fill in the `handleNavigationUpdate` / `setRoute` TODOs to draw the route and
  drive a `CPNavigationSession` with `CPManeuver` + `CPTravelEstimates` from the
  `com.travelapp.car` channel payloads.

## Contract reference
The channel payloads are defined once in
`mobile/lib/services/car_platform_channel.dart` — keep the Swift parsing in sync
with the Kotlin side (`../android_auto/`).
