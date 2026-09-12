# VoyPlan Testing — Android & iOS

## 1. Android Verification
- Flutter Unit & Widget Tests: `flutter test test/toll_test.dart`
- Android Platform Channel Tests: Asserts `MainActivity.kt` arguments parsing for `curLat`, `curLng`, and `bearingDeg`.
- Gradle Build Check: `./gradlew assembleDevDebug --dry-run`.

## 2. iOS Verification
- Flutter iOS Harness: Tests iOS channel dispatch to `CarPlayVoiceGuidance.swift`.
- CocoaPods & Project File Integrity: Verification of `Runner.xcodeproj` schemes and bundle IDs.
