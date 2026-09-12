# VoyPlan — Feature Registry & Cross-Platform Boundaries

| Feature ID | Feature Name | Web Platform | Android App | iOS App | Backend Service | Database Table |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **FEAT-01** | AI Smart Itinerary Planner | Full Web SPA | Flutter Native | Flutter Native | `itineraryEngine.js`, `geminiValidatorService.js` | `trips`, `trip_days`, `trip_stops` |
| **FEAT-02** | Destination Validation | Validation Alert | Validation Alert | Validation Alert | `geminiValidatorService.js` | N/A (Algorithmic) |
| **FEAT-03** | Real-time Road Routing | Leaflet / Mapbox | Mapbox GL SDK | Mapbox GL SDK | `routingService.js` (OSRM/Mapbox) | N/A |
| **FEAT-04** | Toll & Fuel Cost Forecaster | Route Overview | Vehicle Tab | Vehicle Tab | `tollCalculationService.dart`, `fuelService.js` | `vehicles`, `toll_plazas` |
| **FEAT-05** | Trip Editing & Reordering | Drag-and-Drop | ReorderableListView | ReorderableListView | `routes/trip.js` (PUT /api/trips/:id) | `trip_stops` |
| **FEAT-06** | Connected Car Navigation | N/A | `CarNavState.kt` | `CarPlayVoiceGuidance.swift` | WebSocket `ws://...` stream | N/A |
| **FEAT-07** | Supabase Auth & Cloud Sync | OAuth / Password | Supabase Auth | Supabase Auth | `authMiddleware.js` | `auth.users`, `profiles` |
