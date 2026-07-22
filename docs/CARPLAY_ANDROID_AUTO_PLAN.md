# Plan — Native app with Apple CarPlay & Android Auto

> Status: planning. The current product is a **Flutter web app** (deployed to GitHub
> Pages). CarPlay and Android Auto are **impossible from a browser** — they require a
> natively installed, store-distributed app. This document scopes what it takes.

## 1. Key constraints (read first)

1. **Native only.** A web page cannot connect to a car head unit. We need real
   iOS and Android app builds shipped through the App Store / Play Store.
2. **The car screen is not our fancy 3D UI.** CarPlay and Android Auto render
   navigation through **system-provided, driver-distraction-safe templates**.
   The animated 3D globe, the Ferrari model, the cinematic camera, the cartoon
   toll/fuel animations, and the CanvasKit map **do not run on the head unit**.
   The car gets a clean, glanceable turn-by-turn map + maneuver banner + a short
   list of stops. All the rich stuff stays on the **phone** screen.
3. **Approvals are gated.**
   - Apple grants the **CarPlay entitlement** only to apps in the *navigation*
     (or audio/EV/etc.) category, via a request form — not guaranteed.
   - Google reviews Android Auto apps against **driver-distraction guidelines**.
4. **The current web-only rendering must be replaced for mobile.** `dart:html`,
   the inline `index.html` Mapbox JS, the globe, and the Three.js custom-layer
   vehicle are web constructs. On a native app the map becomes a Flutter-native
   Mapbox map.

## 2. Target architecture

```
                       ┌─────────────────────────────────────────┐
                       │  Shared Dart core (reused as-is)          │
                       │  • ApiService / backend calls             │
                       │  • trip planning, tolls, fuel, weather    │
                       │  • vehicles_data, models, auth, saved trips│
                       └─────────────────────────────────────────┘
                              │                         │
             ┌────────────────┘                         └───────────────┐
   ┌───────────────────────┐                          ┌──────────────────────────┐
   │  PHONE UI (Flutter)    │                          │  CAR UI (native modules)  │
   │  • native Mapbox map   │                          │  iOS:  CarPlay framework  │
   │    (mapbox_maps_flutter)│   platform channels /    │        CPMapTemplate,     │
   │  • keep the rich 3D/    │◀───── Pigeon ──────────▶ │        CPNavigationSession│
   │    animations here      │   (route, maneuvers,     │  Android: androidx.car.app│
   │  • trip planner, summary│    stops, ETA, tolls)    │        NavigationTemplate │
   └───────────────────────┘                          └──────────────────────────┘
```

- **Reuse:** backend, trip-planning/toll/fuel/weather logic, vehicle data, auth,
  saved trips, the trip-summary content, POI logic.
- **Rebuild for mobile:** swap the web map for `mapbox_maps_flutter`; drop the
  `dart:html`/`index.html`/globe/Three.js paths behind the existing conditional
  imports so mobile uses native rendering.
- **Net-new:** the two car modules + a real turn-by-turn engine.

## 3. Turn-by-turn engine (needed before either car platform)

The car screen needs real guidance (maneuvers, rerouting, voice). Two options:

| Option | Pros | Cons |
|---|---|---|
| **Mapbox Navigation SDK** (iOS + Android) | Built-in CarPlay & Android Auto support, voice, rerouting | Paid tier (per-MAU/trip), heavier integration |
| DIY on Mapbox Directions API + custom guidance | Full control, cheaper | Must build maneuver logic, rerouting, voice ourselves |

**Recommendation:** Mapbox Navigation SDK — its CarPlay/Android Auto modules
save the most work, and we already use Mapbox.

## 4. Apple CarPlay module

- Framework: `CarPlay` (`CPTemplateApplicationSceneDelegate`, `CPMapTemplate`,
  `CPNavigationSession`, `CPListTemplate` for stops).
- Requires the **CarPlay entitlement** (`com.apple.developer.carplay-maps` for a
  navigation app) — request from Apple with app details; approval not guaranteed.
- Map is drawn by our app into the CarPlay window; Mapbox Nav SDK iOS provides a
  ready CarPlay UI we can adopt.
- Add a second scene in `Info.plist` for the CarPlay window.

## 5. Android Auto module

- Library: `androidx.car.app` (Car App Library) — `CarAppService`,
  `NavigationTemplate`, a `Surface` we render the map into, `Maneuver`/`TravelEstimate`.
- Declare `androidx.car.app.category.NAVIGATION` in the manifest.
- Must pass Google's driver-distraction quality checks; test with the **Desktop
  Head Unit (DHU)** before submitting.
- Mapbox Nav SDK Android has an Android Auto integration we can build on.

## 6. Phased roadmap (rough effort, 1 experienced Flutter+native dev)

| Phase | Work | Est. |
|---|---|---|
| 0. Accounts & entitlements | Apple Dev ($99/yr) + CarPlay entitlement request; Play Console ($25); Mapbox Nav SDK plan | 1 wk (+ Apple approval wait) |
| 1. Mobilize the app | Native Mapbox map for iOS/Android; strip web-only paths; CI for mobile builds | 2–3 wks |
| 2. Turn-by-turn | Integrate Mapbox Navigation SDK; voice; rerouting on the phone | 2–3 wks |
| 3. CarPlay | Scene, map template, nav session, stops list, ETA/toll surfacing | 2–3 wks |
| 4. Android Auto | CarAppService, navigation template, surface rendering, DHU testing | 2–3 wks |
| 5. Compliance & release | Distraction guidelines, real head-unit testing, store review | 2 wks |

**Total: ~3–4 months** for a polished, store-approved result (Apple entitlement
wait can extend this).

## 7. Risks

- **CarPlay entitlement** may be denied or delayed by Apple.
- **Android Auto** store review can require UX changes.
- **Mapbox Navigation SDK cost** scales with usage.
- The current elaborate 3D/animation UX **cannot** appear on the head unit
  (safety) — set expectations that the car view is deliberately minimal.

## 8. Recommended stack

- `mapbox_maps_flutter` (native map on phone)
- Mapbox **Navigation SDK** iOS + Android (guidance + CarPlay/Android Auto)
- `pigeon` for type-safe Flutter⇄native channels
- iOS: `CarPlay` framework, extra `CPTemplateApplicationScene`
- Android: `androidx.car.app` + `CarAppService`

## 9. Interim (ships on the current web app, no native work)

A phone **"Car Mode"**: fullscreen, high-contrast, extra-large buttons, big ETA
and next-maneuver text, voice prompts — for the phone mounted on the dash. Not
CarPlay/Android Auto, but usable in the car today. **✅ Built & shipped** — see
`car_mode_overlay.dart` / `car_guidance_service.dart`.

## 10. Free / open-source stack (avoid the paid Mapbox Navigation SDK)

Everything except the app-store fees can be done with free, open-source tools.
This replaces §3/§8's paid Mapbox Navigation SDK.

### Maps (free, no token)
- **MapLibre GL** — open-source fork of Mapbox GL, free, no token. Flutter:
  `maplibre_gl`; native: MapLibre Native iOS/Android.
- **Tiles:** [OpenFreeMap](https://openfreemap.org/) — completely free, no key, no
  request limits; or [MapTiler](https://www.maptiler.com/cloud/pricing/) free tier
  (100k req/mo). Both serve MapLibre-compatible vector tiles.

### Turn-by-turn navigation SDK (free, open-source)
- **MapLibre Navigation** —
  [android](https://github.com/maplibre/maplibre-navigation-android) + iOS. A
  community fork of the old open Mapbox Nav SDK (v0.19) with **voice guidance,
  route simulation, and a drop-in nav UI**. This is the free replacement for the
  paid Mapbox Navigation SDK. (Caveat: it ships the phone nav UI; the CarPlay /
  Android Auto surface we still wire ourselves onto the free OS frameworks.)

### Routing / directions + maneuvers (free)
- **OpenRouteService** hosted API — free tier **2,500 req/day, 40k/mo**, returns
  turn-by-turn maneuvers. No self-hosting. https://openrouteservice.org/restrictions/
- **Valhalla** public server — [valhalla.openstreetmap.de](https://valhalla.openstreetmap.de),
  free, full-planet, turn-by-turn narrative. Self-host later to scale.
- Alternatives to self-host at scale: **OSRM**, **GraphHopper**, **Valhalla**
  (all open-source, no per-request fees).

### Car frameworks (free)
- Android Auto `androidx.car.app` and iOS `CarPlay` framework are **free** parts
  of the platform SDKs. Test Android Auto free with the **Desktop Head Unit
  (DHU)** + sideloading (no Play account needed for local testing).

### The only unavoidable costs (store distribution)
| Item | Cost | Avoidable? |
|---|---|---|
| Apple Developer Program (ship to App Store **+ CarPlay entitlement**) | $99 / yr | No, to publish/entitle CarPlay |
| Google Play Console (publish Android Auto app) | $25 once | No, to publish |
| Everything else (maps, routing, nav SDK, frameworks) | **$0** | Yes — use the stack above |

On-device dev testing is free (iOS 7-day provisioning, Android sideload + DHU);
only public release and the CarPlay entitlement require the paid Apple program.

### Revised recommended stack
- `maplibre_gl` (free native map) + OpenFreeMap tiles
- **MapLibre Navigation** (free turn-by-turn, voice)
- **OpenRouteService** / **Valhalla** for routes + maneuvers (free)
- `pigeon` for Flutter⇄native channels (free)
- iOS `CarPlay` + Android `androidx.car.app` (free frameworks)
