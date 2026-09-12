# VoyPlan Architecture — Turn-by-Turn Navigation & In-Car Telemetry

## 1. Native Mobile Bridges
- **Android Auto**:
  - Implementation: `mobile/android/app/src/main/kotlin/com/example/travel_app/car/CarNavState.kt` and `CarMapRenderer.kt`.
  - Protocol: Native Flutter platform channel passes `currentLat`, `currentLng`, `bearingDeg`, and `nextManeuver`.
- **Apple CarPlay**:
  - Implementation: `mobile/ios/Runner/CarPlay/CarPlayVoiceGuidance.swift`.
  - Features: Synchronized turn audio voice prompts and maneuver cards.

## 2. In-Drive Re-routing
- If GPS deviations exceed 250 meters from the planned corridor, the client initiates an automatic recalculation request to `/api/route` while preserving downstream destination anchors.
