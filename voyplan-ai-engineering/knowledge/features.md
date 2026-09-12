# VoyPlan Existing Features Matrix & Dependency Map

## 1. Core Feature Matrix

| Feature | Surface | Backend API | Dependencies | Existing Protection Rules |
| :--- | :--- | :--- | :--- | :--- |
| **One-Way Road Trip** | Mobile / Web | `/api/ai/smart-itinerary`, `/api/routing/route` | OSRM router, Geocoding | Trip finishes at destination; must never generate return block. |
| **Around / Round Trip** | Mobile / Web | `/api/ai/smart-itinerary`, `/api/routing/route` | OSRM router, Geocoding | Trip anchors on destination, visits sights, returns to starting origin on last day. |
| **AI Itinerary Planner** | Mobile / Web | `/api/ai/smart-itinerary` | `itineraryEngine.js`, `geminiValidatorService.js` | Destination must control itinerary generation; never pull unrelated cities. |
| **Dynamic Fuel Calculation** | Mobile / Web | `/api/fuel/calculate` | `fuelRangeService.js`, `fuelPriceProvider.js` | Refuel stops injected before tank falls below 15% reserve. |
| **Toll Estimation** | Mobile / Web | `/api/routing/tolls` | `tollService.js`, TollGuru | High-precision expressway toll calculation with vehicle class. |
| **Active "Today" Mode** | Mobile / Web | `/api/trip/active` | Flutter state, GPS / Geolocator | Current block highlight, turn-by-turn routing to next stop. |
| **Vehicle Profiles** | Mobile / Web | `/api/vehicles` | Supabase `user_vehicles` | User vehicle efficiency, tank size, and fuel type. |
| **Trip Sharing & Sync** | Mobile / Web / Auto | `/api/trip/share`, WebSocket | Supabase `shared_trips`, `ws` server | Real-time cross-device sync with token validation. |

## 2. Interaction & Regression Impact Matrix
When modifying the **AI Itinerary Engine**, you MUST test:
1. Trip creation flow in Flutter.
2. Trip editing flow and stop deletion.
3. Destination selection & autocomplete.
4. Route calculation and distance totals.
5. Fuel stop insertion.
6. Return-to-origin block generation on multi-day round trips.
7. Map markers and polyline rendering.
