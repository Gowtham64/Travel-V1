# VoyPlan Architecture — API Contract

## 1. REST Endpoints
- `POST /api/ai/smart-itinerary`: Generates validated multi-day itinerary.
  - Body: `{ origin: "string|object", destination: "string|object", startDate, endDate, pace, categories: [] }`
  - Returns: `{ days: [...], polyline: "...", totalDistanceKm, totalDurationMinutes }`
- `GET /api/trips/:id`: Retrieves full trip with days and stops.
- `PUT /api/trips/:id/stops/reorder`: Updates sequence and order indices of itinerary stops.
- `POST /api/route`: Computes OSRM road geometry between waypoints.
- `GET /api/geocode/search?q=...`: Searches places and coordinates.
- `POST /api/vehicle/fuel-estimate`: Calculates consumption and refill costs.

## 2. WebSocket Protocol (`ws://localhost:3000/ws`)
- `action: "nav_update"`: Sends real-time GPS position, speed, and heading.
- `action: "car_state"`: Synchronizes Android Auto / CarPlay navigation state.
