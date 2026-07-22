# Android Auto integration

Scaffolding for the Android Auto navigation app. **Not yet compiled** — integrate
on a machine with the Android SDK and test with the Desktop Head Unit (DHU).

## 1. Add the dependency
In `mobile/android/app/build.gradle.kts`, inside `dependencies { }`:
```kotlin
implementation("androidx.car.app:app:1.4.0")
// If you later add the Automotive OS target too: androidx.car.app:app-automotive
```
(Requires `compileSdk` 34+, already satisfied by the Flutter default.)

## 2. Place the Kotlin files
Move into `mobile/android/app/src/main/kotlin/io/github/gowtham64/travelapp/car/`:
- `CarAppService.kt`
- `NavigationScreen.kt`

(The package `io.github.gowtham64.travelapp.car` must match the folder path. The
app's current Kotlin `namespace` is `com.example.travel_app`; either keep this
`car` package under that namespace's folder tree, or align both — but do NOT
change `applicationId`, which is the store identity.)

## 3. Merge the manifest
Apply `AndroidManifest.additions.xml` into
`mobile/android/app/src/main/AndroidManifest.xml`, and create
`res/xml/automotive_app_desc.xml`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<automotiveApp>
    <uses name="navigation" />
</automotiveApp>
```

## 4. Bridge the Flutter MethodChannel → CarNavState
The car service runs in the same process but a **different task** than the Flutter
activity. Register the `com.travelapp.car` channel in `MainActivity` and push
updates into the `CarNavState` singleton:

```kotlin
// MainActivity.kt
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.github.gowtham64.travelapp.car.CarNavState

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.travelapp.car")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setNavigationState" -> {
                        CarNavState.isNavigating = call.argument<Boolean>("isNavigating") ?: false
                        CarNavState.notifyChanged(); result.success(null)
                    }
                    "updateNavigation" -> {
                        CarNavState.instruction = call.argument<String>("instruction") ?: ""
                        CarNavState.maneuverType = call.argument<String>("maneuverType") ?: "straight"
                        CarNavState.distanceMeters = call.argument<Double>("distanceMeters") ?: 0.0
                        CarNavState.remainingDistanceKm = call.argument<Double>("remainingDistanceKm") ?: 0.0
                        CarNavState.remainingDurationMin = call.argument<Int>("remainingDurationMin") ?: 0
                        CarNavState.notifyChanged(); result.success(null)
                    }
                    "setRoute" -> { /* TODO: store route polyline for the map surface */ result.success(null) }
                    else -> result.notImplemented()
                }
            }
    }
}
```
> Note: when Android Auto starts the car app independently of the phone activity,
> the Flutter engine may not be running. For production, host the Flutter engine
> in a `FlutterEngineGroup`/foreground service, or persist the last route so the
> car app can render without the phone UI open. This is the main integration task
> beyond the scaffolding.

## 5. Test with the DHU (free, no Play account)
```bash
sdkmanager "extras;google;auto"          # installs the Desktop Head Unit
# Enable "Unknown sources" + "Start head unit server" in the Android Auto app,
# connect the phone via USB, then:
$ANDROID_HOME/extras/google/auto/desktop-head-unit
```
Validate against the driver-distraction guidelines before submitting.
