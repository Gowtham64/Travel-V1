# VoyPlan Architecture — Backend Services

## 1. Core Runtime
- Node.js 20, Express 4.19.2. Entry point: `backend/src/index.js`.
- HTTP Security: `helmet()`, `cors()`, `express-rate-limit`.

## 2. Key Modules
- `services/itineraryEngine.js`: Assembles day-by-day travel blocks, activities, meal breaks, and transit legs.
- `services/geminiValidatorService.js`: Deterministic validation layer enforcing destination locks, Haversine boundaries (<75km), and forbidden city clusters.
- `services/routingService.js`: Queries OSRM or Mapbox for driving polyline geometries and leg distances.
- `services/geocodeService.js`: Forward and reverse geocoding via Mapbox & Pelias.
- `services/fuelService.js`: Fuel cost estimation and station waypoint injection.
