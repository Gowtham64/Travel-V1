# VoyPlan API Architecture & Contract Specification

## 1. Protocol & Conventions
- **Base URL**: `/api`
- **Transport**: HTTPS & WSS (Secure WebSockets)
- **Format**: JSON (Request & Response)
- **Headers**:
  - `Content-Type: application/json`
  - `Authorization: Bearer <supabase-jwt>` (for authenticated endpoints)

## 2. API Endpoints

### AI & Itinerary Planning (`/api/ai`)
- `POST /api/ai/smart-itinerary`:
  - **Body**:
    ```json
    {
      "startLocation": "Bengaluru",
      "destination": "Tirumala",
      "tripType": "around",
      "durationDays": 2,
      "mode": "balanced",
      "selectedCategories": ["Temples"],
      "vehicleType": "car",
      "fuelEfficiency": 15,
      "tankCapacity": 45,
      "currentFuel": 30
    }
    ```
  - **Response 200**:
    ```json
    {
      "destinationPoint": { "name": "Tirumala", "lat": 13.6833, "lng": 79.3473, "locked": true },
      "totalDistanceKm": 540.2,
      "days": [ { "day": 1, "blocks": [...] } ],
      "budget": { ... }
    }
    ```
  - **Response 422**: Rejection feedback with required corrections if validator loop fails.
- `POST /api/ai/recommend`: Suggests en-route POIs between start, end, and waypoints.
- `POST /api/ai/search`: Natural language place lookup.
- `POST /api/ai/travel-options`: Typical flight, rail, and hotel estimates.
- `GET /api/ai/status`: Reports configured AI provider, active model, and health status (no secrets).

### Navigation & Routing (`/api/routing`)
- `POST /api/routing/route`:
  - **Body**: `{ "origin": { "lat": ..., "lng": ... }, "destination": { ... }, "waypoints": [ ... ] }`
  - **Response**: GeoJSON polyline geometry, driving distance (meters), duration (seconds), and step instructions.

### Geocoding (`/api/geocode`)
- `GET /api/geocode/search?q=<query>&near=<focus>`: Forward geocoding.
- `GET /api/geocode/reverse?lat=<lat>&lng=<lng>`: Reverse geocoding.

### Trip Persistence & Collaboration (`/api/trip`)
- `POST /api/trip`: Create / save trip.
- `GET /api/trip/:id`: Retrieve full trip itinerary and route geometry.
- `PUT /api/trip/:id`: Update trip blocks and schedule.
- `DELETE /api/trip/:id`: Archive / delete trip.

### System & Health (`/api/status`)
- `GET /api/status`: Uptime, Node version, memory usage, environment indicator.
