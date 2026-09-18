# VoyPlan Backend API Documentation

## 1. Overview & Base URL

- **Production URL**: `https://api.voyplan.in` (Render Web Service)
- **Local Dev URL**: `http://localhost:3000`
- **Protocol**: HTTPS required in production.
- **Content Type**: `application/json`

---

## 2. System Probes

### `GET /health`
Liveness probe. Used by load balancers, Render zero-downtime health checkers, and uptime monitors.

**Response (HTTP 200 OK):**
```json
{
  "status": "ok",
  "version": "2.4.0",
  "timestamp": "2026-09-18T13:40:00.000Z"
}
```

---

### `GET /ready`
Readiness probe. Verifies active database connectivity to Supabase Postgres and environment configuration.

**Success Response (HTTP 200 OK):**
```json
{
  "status": "ready",
  "version": "2.4.0",
  "checks": {
    "database": "connected",
    "environment": "healthy"
  },
  "timestamp": "2026-09-18T13:40:00.000Z"
}
```

**Degraded Response (HTTP 503 Service Unavailable):**
```json
{
  "status": "degraded",
  "version": "2.4.0",
  "error": "Database unreachable",
  "timestamp": "2026-09-18T13:40:00.000Z"
}
```

---

## 3. Vehicle & Fuel Endpoints

### `GET /api/vehicles/brands`
Returns the list of supported automobile manufacturers. Cached at the edge with `gzip` compression.

**Headers:**
- `Cache-Control: public, max-age=86400`
- `Content-Encoding: gzip`

**Example Request:**
```bash
curl -s https://api.voyplan.in/api/vehicles/brands
```

---

### `GET /api/fuel/prices`
Fetches current state/national fuel rates (petrol, diesel, CNG, EV kWh rates).

**Parameters:**
- `country` (query string, e.g. `IN`, `US`, default: `IN`)

**Example Request:**
```bash
curl -s "https://api.voyplan.in/api/fuel/prices?country=IN"
```

---

## 4. AI & Routing Endpoints

### `POST /api/ai/smart-itinerary`
Generates optimized itinerary stops and activities using the Python AI microservice with fallback logic.

**Request Body:**
```json
{
  "origin": "Bengaluru",
  "destination": "Goa",
  "days": 3,
  "travelStyle": "adventure",
  "budget": "moderate"
}
```

---

### `GET /api/geocode/suggest`
Provides autocomplete suggestions for places, landmarks, and addresses.

**Parameters:**
- `q` (query string, minimum 2 characters)

**Example Request:**
```bash
curl -s "https://api.voyplan.in/api/geocode/suggest?q=Mysore"
```

---

## 5. Telemetry & Metrics

### `GET /api/metrics`
Exposes application health metrics and response bandwidth counters.

**Response:**
```json
{
  "status": "ok",
  "uptimeSeconds": 14502,
  "telemetry": {
    "totalRequests": 1840,
    "totalResponseBytes": 4291040
  }
}
```
