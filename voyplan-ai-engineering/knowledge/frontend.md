# VoyPlan Frontend Architecture

## 1. Framework & Core Stack
- **Framework**: Flutter (SDK `>=3.3.0 <4.0.0`, Dart 3.x)
- **Compilation Targets**:
  - **Web SPA**: CanvasKit/HTML compiled into `mobile/build/web` and hosted at `/app/`.
  - **Android**: Multi-flavor setup (`prod`, `staging`, `dev`) side-by-side installations:
    - Prod: `io.github.gowtham64.travelapp`
    - Staging: `io.github.gowtham64.travelapp.staging`
    - Dev: `io.github.gowtham64.travelapp.dev`
  - **iOS**: Target with CocoaPods and Apple developer signing profiles.

## 2. State Management & Navigation
- **State Architecture**: `provider: ^6.1.2` (ChangeNotifier providers)
- **Key Services**:
  - `trip_provider.dart`: Current trip state, daily blocks, active waypoints, route metrics.
  - `auth_service.dart`: Supabase session lifecycle and user credentials.
  - `fuel_price_service.dart`: Live dynamic fuel calculation and expense tracking.
  - `toll_calculation_service.dart`: Highway toll estimation.
  - `car_nav_state.dart`: Android Auto / Apple CarPlay navigation bridge.

## 3. UI Screen Flows
1. **Home Screen (`home_screen.dart`)**:
   - Destination search bar with autocomplete
   - Trip creation wizard (One-Way vs Around/Round Trip)
   - Date range and start time picker
   - Category selector (Temples, Hills, Beaches, Historical, Wildlife, Nature)
   - Mode & pace selector (Relaxed, Balanced, Packed)
2. **Itinerary View (`itinerary_screen.dart`)**:
   - Timeline cards per day with category badges
   - Dynamic travel legs with calculated driving time and distance
   - Meal stops, check-in/out, and destination anchor blocks
   - "Today" active execution mode
3. **Map & Navigation View (`map_view.dart`)**:
   - Interactive OpenStreetMap/Mapbox rendering (`flutter_map: ^7.0.2` / `maplibre_gl: ^0.26.2`)
   - Route polyline overlay with waypoint markers and gas station / rest stop pins
4. **Budget & Vehicle Management**:
   - Vehicle selector (Car, SUV, Bike, EV) with efficiency & tank capacity sliders
   - Live fuel expense calculation and breakdown

## 4. Environment Injection
Values are injected compile-time via `--dart-define`:
```bash
--dart-define=APP_ENV=production|staging|development
--dart-define=BACKEND_URL=https://travel-v1-mzia.onrender.com
--dart-define=SUPABASE_URL=https://dtemayjpttktntooxraa.supabase.co
--dart-define=SUPABASE_ANON_KEY=...
--dart-define=MAPBOX_TOKEN=pk....
```
Defaults fall back to Production in source code (`mobile/lib/config/app_config.dart`).
