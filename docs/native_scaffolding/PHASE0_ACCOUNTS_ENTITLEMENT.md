# Phase 0 — Accounts, fees & the CarPlay entitlement

These are the human/legal/payment steps that **cannot be automated**. Everything
in the sibling `carplay/`, `android_auto/`, and `MAPLIBRE_MIGRATION.md` files is
the code that plugs in once these are in place.

## 0.1 Apple Developer Program — required for CarPlay
- **Cost:** $99 / year.
- **Enroll:** https://developer.apple.com/programs/enroll/ (needs an Apple ID and,
  for an org, a D-U-N-S number).
- **App identifier:** register the bundle ID already set in the project —
  `io.github.gowtham64.travelApp` — at
  https://developer.apple.com/account/resources/identifiers/list

## 0.2 CarPlay entitlement request (the long pole)
CarPlay is a **restricted entitlement**; you must request it and be approved.
- **Request form:** https://developer.apple.com/contact/request/carplay/
- **App category to request:** *Navigation* → entitlement
  `com.apple.developer.carplay-maps`.
- **What Apple asks for (draft answers below):**

  > **App name:** Travel App
  > **What does your app do?** A road-trip planner with turn-by-turn navigation:
  > intelligent multi-stop routing on real road networks, live GPS guidance with
  > voice, route weather, fuel/toll cost estimates, and point-of-interest
  > discovery (fuel, EV charging, food, stays, attractions) along the route.
  > **Why does it need CarPlay?** To provide safe, glanceable turn-by-turn
  > navigation on the vehicle head unit while the rich planning UI stays on the
  > phone. It uses the standard `CPMapTemplate` / `CPNavigationSession` driving
  > templates — no custom distracting UI on the car screen.
  > **Navigation category:** Yes — the app provides real point-to-point road
  > navigation with maneuvers, ETA, and rerouting.

- **Approval is not guaranteed and can take days–weeks.** Start this first; the
  code can be built while you wait.
- Once approved, add the entitlement to `ios/Runner/Runner.entitlements`:
  ```xml
  <key>com.apple.developer.carplay-maps</key>
  <true/>
  ```
  and enable it on the App ID in the developer portal.

## 0.3 Google Play Console — required for Android Auto
- **Cost:** $25 one-time.
- **Register:** https://play.google.com/console/signup
- Android Auto **navigation** apps are reviewed against the Driver Distraction
  guidelines: https://developer.android.com/training/cars/driver-distraction
- No special entitlement request like Apple — but the app must pass the
  automated + manual review and be tested with the **Desktop Head Unit (DHU)**.

## 0.4 What you can test WITHOUT the above
- **Android Auto:** free locally — install the APK, enable Developer mode in the
  Android Auto app, and run the **DHU** (`sdkmanager "extras;google;auto"`), no
  Play account needed. See `android_auto/README.md`.
- **CarPlay:** the **Xcode CarPlay simulator** (I/O ▸ External Displays ▸ CarPlay
  in the iOS Simulator) lets you see the templates without a car — but building
  to it still needs the Apple Developer account + entitlement for a device.

## 0.5 Cost summary
| Item | Cost | Blocking? |
|---|---|---|
| Apple Developer Program (+ CarPlay entitlement) | $99/yr | Yes, to ship/entitle CarPlay |
| Google Play Console | $25 once | Yes, to publish Android Auto |
| Maps, routing, nav, frameworks | $0 | Uses the free/open-source stack |

## 0.6 Order of operations
1. Enroll Apple Dev + submit the **CarPlay entitlement request now** (long wait).
2. Register the Play Console.
3. While waiting: integrate `android_auto/` (test on DHU) and `carplay/`
   (test in the CarPlay simulator), and apply `MAPLIBRE_MIGRATION.md`.
4. On entitlement approval: add `Runner.entitlements`, sign, and submit both.
