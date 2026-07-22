# Native scaffolding — CarPlay & Android Auto

Ready-to-apply artifacts for the native car track (plan phases 0, 2, 3, 4 in
`../CARPLAY_ANDROID_AUTO_PLAN.md`). These are **not compiled by CI** on purpose:
they need the Android/iOS toolchains and real device / head-unit testing to
integrate, so keeping them out of the build keeps `main` green and trustworthy.

| File | Phase | What it is |
|---|---|---|
| `PHASE0_ACCOUNTS_ENTITLEMENT.md` | 0 | Apple/Google account steps + the CarPlay entitlement request draft (human-only, can't be automated). |
| `android_auto/` | 4 | `CarAppService` + `NavigationScreen` Kotlin, manifest additions, and the MethodChannel bridge + DHU test steps. |
| `carplay/` | 3 | `CarPlaySceneDelegate` Swift, Info.plist scene, entitlement, and shared-engine wiring. |
| `MAPLIBRE_MIGRATION.md` | 1 (opt) | Swap the mobile raster map for a free MapLibre GL vector map (drop-in `ThreeDMap`). |

## What already landed in the build (verifiable)
- **Phase 1:** native iOS + Android build green on CI (`.github/workflows/mobile-build.yml`); real bundle IDs; `dart:html` leak fixed.
- **Phase 2 (partial):** `CarGuidanceService.buildManeuverList()` (full-route step
  list for the car screen) and `isOffRoute()` (reroute trigger) — Dart, analyzer-clean.
- The car contract seam `lib/services/car_platform_channel.dart` (`com.travelapp.car`)
  is what both native modules implement.

## Integration order
1. `PHASE0_...` — enroll + request the CarPlay entitlement (long wait; start now).
2. `MAPLIBRE_MIGRATION.md` — optional, on a branch, CI-verified.
3. `android_auto/` — integrate + test on the DHU (free).
4. `carplay/` — integrate + test in the CarPlay simulator; ship after entitlement approval.
