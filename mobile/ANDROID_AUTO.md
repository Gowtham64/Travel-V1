# Android Auto navigation

The app projects its active route + turn-by-turn guidance onto an Android Auto
head unit. This is a **native Android** feature — it does **not** work from the
web build, only from an installed APK.

## Architecture

```
Flutter (trip_screen)
  └─ CarPlatformChannel  --MethodChannel "com.travelapp.car"-->  MainActivity
                                                                    └─ CarNavState (shared singleton)
                                                                         └─ NavigationScreen (Android Auto)
```

- `lib/services/car_platform_channel.dart` — sends `setRoute`, `updateNavigation`, `setNavigationState`.
- `android/.../car/CarNavState.kt` — process-wide state bridge + position estimate.
- `android/.../car/TravelCarAppService.kt` / `TravelSession.kt` / `NavigationScreen.kt` — the Android Auto app (NavigationTemplate + map surface).
- `android/.../MainActivity.kt` — registers the channel and feeds `CarNavState`.

## Build & test

Requires a machine with a JDK + Android SDK (Android Studio).

```bash
cd mobile
flutter build apk            # or: flutter run  (to a connected phone)
```

On the phone:
1. Install the APK.
2. Settings → Android Auto → tap the version ~10× → enable **Developer mode**.
3. Developer settings → enable **Unknown sources** (required for a sideloaded nav app).

Test without a car using the **Desktop Head Unit (DHU)**:
```bash
sdkmanager "extras;google;auto"      # installs the DHU
adb forward tcp:5277 tcp:5277
"$ANDROID_HOME/extras/google/auto/desktop-head-unit"
```
Start a trip in the app → the route + guidance appear on the head unit.

## Notes / limits

- Android Auto renders a **template UI** (map surface + guidance card + ETA), not
  a mirror of the phone's Flutter screens — this is Google's driver-safety model.
- Public release requires **Google Play review** (Navigation app category).
  Developer/DHU testing does not.
- `minSdk` is raised to ≥23 (the `androidx.car.app` floor).
