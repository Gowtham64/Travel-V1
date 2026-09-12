# VoyPlan — Overall Architecture Topology

```
┌────────────────────────────────────────────────────────────────────────┐
│                          VOYPLAN CLIENTS                               │
│   Web SPA (Flutter Web)      Android (Flutter + Kotlin)     iOS (Flutter + Swift)
│   Host: voyplan.in           Flavors: prod, staging, dev    CarPlay Voice Integration
└───────────────┬──────────────────────────┬─────────────────────────────┘
                │                          │
                ▼                          ▼
         REST API (HTTPS)          WebSocket (WSS)
                │                          │
┌───────────────┴──────────────────────────┴─────────────────────────────┐
│                          BACKEND API SERVER                            │
│                       Node.js 20 + Express 4.19.2                      │
│                                                                        │
│  Controllers & Routes:                                                 │
│  • /api/ai/smart-itinerary  • /api/trips     • /api/geocode            │
│  • /api/route               • /api/vehicle   • /api/toll               │
│                                                                        │
│  Core Engines:                                                         │
│  • itineraryEngine.js      (Schedule assembly & timing)                │
│  • geminiValidatorService  (Spatial bounding & deterministic QC)       │
│  • routingService.js       (OSRM / Mapbox Directions)                  │
│  • geocodeService.js       (Pelias / Mapbox Geocoding)                 │
└───────────────┬──────────────────────────┬─────────────────────────────┘
                │                          │
                ▼                          ▼
        EXTERNAL SERVICES          PERSISTENCE LAYER
        • OSRM Router               • Supabase PostgreSQL
        • Mapbox API                • PostGIS (Spatial indexing)
        • Gemini Generative AI      • Local Hive Cache (Mobile)
```
