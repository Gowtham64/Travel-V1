# VoyPlan Architecture — Frontend (Flutter Web & Mobile)

## 1. Structure
- Root: `mobile/lib/`
- Framework: Flutter 3.3.0+ (Dart 3)
- Screens: `screens/itinerary_screen.dart`, `screens/navigation_screen.dart`, `screens/trip_detail_screen.dart`, `screens/vehicle_setup_screen.dart`.
- Services: `services/api_service.dart`, `services/car_platform_channel.dart`, `services/trip_history_service.dart`, `services/toll_calculation_service.dart`.
- State Management: Provider / ChangeNotifier with scoped reactive rebuilds.

## 2. Cross-Platform Compilation
- **Web SPA**: Built via `flutter build web --release --base-href /app/`, deployed alongside static landing pages into `public/`.
- **Android**: Flavors `prod`, `staging`, `dev` with custom `MainActivity.kt` and `CarNavState.kt`.
- **iOS**: Target `Runner` with CarPlay audio guidance in `CarPlayVoiceGuidance.swift`.
