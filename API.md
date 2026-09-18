# VoyPlan API

## Base URLs

- Production: `https://api.voyplan.in`
- Local development: `http://localhost:3000`

The production API is a Cloudflare Worker. Requests and responses use JSON over HTTPS.

## Service probes

### `GET /health`

Liveness probe for the deployed Worker. A healthy response is HTTP 200 with `status: "ok"`, service metadata, and a timestamp.

### `GET /ready`

Readiness probe. It checks Worker configuration and Supabase connectivity; it returns HTTP 200 with `status: "ready"` or HTTP 503 with `status: "degraded"`.

## Authentication

Protected routes require:

```text
Authorization: Bearer <Supabase access token>
```

The Worker validates the token with Supabase and returns HTTP 401 for invalid or missing credentials.

## API groups

The Worker exposes routes for trip planning, AI itinerary generation, geocoding, vehicles, fuel, prices, accounts, currency, treks, status, and metrics. Consult `cloudflare-worker/src/index.ts` and the route modules for the current request schemas; those files are the implementation source of truth.
