# VoyPlan Platform — Android Architecture

## 1. Project Topology
- Directory: `mobile/android/`
- Build System: Gradle Kotlin DSL (`build.gradle.kts`)
- Min SDK: 21, Target SDK: 34
- Flavors: `dev`, `staging`, `prod`

## 2. In-Vehicle Connected Android Auto
- `MainActivity.kt`: Platform channel bridge for GPS coordinate feeds.
- `CarNavState.kt`: Singleton tracking `curLat`, `curLng`, and `bearing`.
- `CarMapRenderer.kt`: Android Auto surface drawing and maneuver cues.
