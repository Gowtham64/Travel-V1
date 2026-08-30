# iOS Live Activity (Dynamic Island + lock-screen trip tracker)

The Dart side (`LiveActivityService`), the notification wiring, the SwiftUI
Live Activity, the shared attributes and the app-side manager are all written
and in the repo. Two things remain that can only be done in Xcode / with an
Apple account — they are intentionally **not** auto-applied so the current
free-sideload build keeps working:

1. Add a **Widget Extension target** (Live Activities can only render from a
   widget extension).
2. **Enroll in the paid Apple Developer Program** — Live Activities do not run
   reliably under free provisioning.

Until both are done, the app runs normally and the Live Activity calls no-op.
The Android live notification and the iOS local notification already work.

---

## Files already in the repo

- `ios/VoyplanTripActivity/TripActivityAttributes.swift` — shared model
- `ios/VoyplanTripActivity/VoyplanTripActivityLiveActivity.swift` — the widget UI
- `ios/VoyplanTripActivity/VoyplanTripActivityBundle.swift` — widget entry point
- `ios/Runner/LiveActivityManager.swift` — app-side start/update/end
- `ios/Runner/Info.plist` — already has `NSSupportsLiveActivities = true`
- `lib/services/live_activity_service.dart` — Dart bridge (channel `com.travelapp.liveactivity`)

## Steps

1. **Open the workspace**: `open ios/Runner.xcworkspace`
2. **Raise the deployment target** of Runner to **iOS 16.1+** (or guard is fine,
   but 16.1 is required for ActivityKit).
3. **File → New → Target… → Widget Extension**. Name it `VoyplanTripActivity`,
   tick **Include Live Activity**, uncheck "Include Configuration App Intent".
   Finish, and let Xcode create the scheme.
4. **Replace** the extension's generated files with the three files already in
   `ios/VoyplanTripActivity/` (or delete Xcode's and drag these in). Ensure they
   are members of the **VoyplanTripActivity** target.
5. **Add `TripActivityAttributes.swift` to BOTH targets**: select it, open the
   File Inspector, and tick **Runner** *and* **VoyplanTripActivity** under
   Target Membership.
6. **Add `LiveActivityManager.swift` to the Runner target** (tick Runner).
7. **Wire the channel** — add to `ios/Runner/AppDelegate.swift`:

   ```swift
   import Flutter
   import UIKit

   @main
   @objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
     override func application(
       _ application: UIApplication,
       didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
     ) -> Bool {
       if let controller = window?.rootViewController as? FlutterViewController {
         let channel = FlutterMethodChannel(
           name: "com.travelapp.liveactivity",
           binaryMessenger: controller.binaryMessenger)
         channel.setMethodCallHandler { call, result in
           guard #available(iOS 16.1, *) else { result(nil); return }
           let args = call.arguments as? [String: Any] ?? [:]
           switch call.method {
           case "start":
             LiveActivityManager.shared.start(
               destination: args["destination"] as? String ?? "Trip")
           case "update":
             LiveActivityManager.shared.update(
               eta: args["eta"] as? String ?? "",
               distanceLeftKm: args["distanceLeftKm"] as? Double ?? 0,
               progress: args["progress"] as? Double ?? 0,
               arriving: args["arriving"] as? Bool ?? false)
           case "end":
             LiveActivityManager.shared.end()
           default: break
           }
           result(nil)
         }
       }
       return super.application(application, didFinishLaunchingWithOptions: launchOptions)
     }

     func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
       GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
     }
   }
   ```

8. **Signing**: with a **paid** Apple Developer account, select both the Runner
   and VoyplanTripActivity targets → Signing & Capabilities → your team. Each
   target needs its own bundle id (e.g. `com.gowtham.travelapp` and
   `com.gowtham.travelapp.VoyplanTripActivity`).
9. Build & run on device. Start a trip → the Live Activity appears on the lock
   screen and Dynamic Island, updating live via the same telemetry that already
   drives the Android notification.

No Dart changes are needed — `TripNotificationService` already calls
`LiveActivityService.start/update/end` on every trip.
