# Travel app backend

Express API that powers the travel app: routing, day estimation, fuel/refuel planning,
toll estimates, and points of interest along a route. Built entirely on free/open-source
services - see the main project README for the full API list.

## Setup

```bash
cd backend
npm install
cp .env.example .env   # then fill in ORS_API_KEY and TOLLGURU_API_KEY
npm start              # or: npm run dev (auto-restarts on file changes)
```

The server listens on `http://localhost:3000` by default.

## Getting your free API keys

- **OpenRouteService** (routing): sign up free at https://openrouteservice.org/dev/#/signup
- **TollGuru** (tolls): sign up free at https://tollguru.com/dashboard (use a business email
  for a higher daily quota - 150/day vs 15/day on a personal email)
- **Overpass API** (fuel stations, hotels, restaurants, attractions): no key needed, it's a
  fully open public API

## Running the tests

```bash
npm test
```

Tests cover:
- `geo.test.js` - distance math (haversine, cumulative route distance)
- `fuelService.test.js` - range calculation, refuel stop detection, trip day estimation
- `trip.route.test.js` - the `/api/trip/plan` endpoint, with external API calls mocked so
  tests run fully offline

## API

### `GET /health`
Returns `{ "status": "ok" }` - use this to check the server is running.

### `POST /api/trip/plan`

Request body:
```json
{
  "start": { "lat": 12.9716, "lng": 77.5946 },
  "end": { "lat": 13.0827, "lng": 80.2707 },
  "vehicle": {
    "type": "car",
    "efficiencyKmPerLiter": 15,
    "tankCapacityLiters": 40,
    "currentFuelLiters": 30
  },
  "dailyDrivingHours": 7,
  "includePlaces": ["restaurant", "hotel", "fuel"]
}
```

`vehicle.type` accepts: `car`, `suv`, `motorcycle`, `bus`, `rv`, `truck2axle`, `truck3axle`
(mapped to TollGuru's vehicle classes - see `src/services/tollService.js`).

`includePlaces` is optional - each category you list triggers an extra Overpass API call
to find that type of place along the route. Leave it empty for the fastest response.

Response shape:
```json
{
  "route": { "distanceKm": 350, "durationMin": 360, "coordinates": [...] },
  "estimatedDays": 1,
  "fuel": {
    "needsRefuel": true,
    "totalDistanceKm": 350,
    "refuelStops": [{ "lat": 13.2, "lng": 78.1, "distanceFromStartKm": 240 }]
  },
  "toll": {
    "hasTolls": true,
    "currency": "INR",
    "minTollCost": 180,
    "maxTollCost": 210,
    "fuelCost": 1450
  },
  "places": {
    "restaurant": [{ "id": 123, "name": "...", "lat": 13.1, "lng": 78.0 }]
  }
}
```

`toll` will be `null` if the TollGuru call fails or the free daily quota is exhausted -
the rest of the trip plan still returns normally.

## Notes / known gaps to fill in next

- No caching layer yet - every call hits the live APIs. Add a Postgres/Supabase cache
  keyed by rounded start/end coordinates + vehicle type before this goes to production,
  since all the free tiers here have daily caps.
- `findPlacesAlongRoute` samples the route every 25km by default - tune `sampleEveryKm`
  per category (you probably want fuel stations checked more often than hotels).
- Attribution: since routing and places data comes from OpenStreetMap, the app's
  About/Settings screen needs an "© OpenStreetMap contributors" notice.
