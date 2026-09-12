# VoyPlan Backend Architecture

## 1. Core Framework & Entrypoint
- **Runtime**: Node.js 20 LTS
- **Server Framework**: Express 4.19.2
- **Port**: 3000 (configurable via `PORT`)
- **Security Middleware**:
  - `helmet: ^8.3.0` for HTTP security headers
  - `cors: ^2.8.5` for cross-origin permissions
  - `express-rate-limit: ^8.6.1` for API throttling
  - `ws: ^8.21.0` WebSocket server for live vehicle and trip synchronization

## 2. Directory Layout
```
backend/src/
├── index.js                     # Express app & WebSocket server setup
├── routes/
│   ├── ai.js                    # Itinerary generation & AI recommendations
│   ├── trip.js                  # Trip persistence, sharing, and synchronization
│   ├── routing.js               # Direction calculation & polyline generation
│   ├── geocode.js               # Mapbox & ORS forward/reverse geocoding
│   ├── fuel.js                  # Fuel price providers and range calculation
│   ├── vehicles.js              # Vehicle specs and database syncing
│   ├── account.js               # User profiles and preferences
│   ├── currency.js              # Foreign currency conversions
│   ├── prices.js                # Flight/Hotel/Train typical pricing
│   └── status.js                # Health checks & uptime metrics
├── services/
│   ├── aiService.js             # Multi-provider LLM abstraction (Gemini, Groq, OpenRouter)
│   ├── itineraryEngine.js       # Deterministic itinerary generator & scheduler
│   ├── geminiValidatorService.js# AI validation & deterministic destination guardrails
│   ├── itineraryGeo.js          # Grounding AI draft legs with OSRM and Pelias
│   ├── routingService.js        # Multi-provider routing (OSRM, Mapbox, ORS)
│   ├── geocodeService.js        # Pelias & Mapbox geocoding
│   ├── fuelRangeService.js      # Range calculations and refueling stop planning
│   ├── tollService.js           # TollGuru highway toll estimation
│   ├── dbService.js             # Supabase PostgreSQL client
│   └── vehicleSyncService.js    # Real-time WebSocket state distribution
└── tests/                       # Jest unit & integration test suites
```

## 3. Key Algorithms & Pipelines
1. **Hybrid AI-Deterministic Planning**:
   - Initial candidate retrieval anchored on origin & locked destination coordinates.
   - Stop ordering by spatial progression and visit duration heuristics.
   - Pacing adjustment (Relaxed: 4h travel max; Packed: 9h travel max).
2. **Refueling Calculation**:
   - Computes vehicle range from current tank level, tank capacity, and fuel efficiency (km/L).
   - Injects gas station stops before fuel drops below 15% reserve.
3. **Route Distance Grounding**:
   - Replaces AI text estimates with authoritative OSRM / Mapbox driving distances.
