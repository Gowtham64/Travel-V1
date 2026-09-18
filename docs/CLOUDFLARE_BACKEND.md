# VoyPlan Cloudflare Workers Backend API

## Overview
VoyPlan's production backend API is hosted on **Cloudflare Workers** at `https://api.voyplan.in`. It runs as a globally distributed, high-performance edge service on the V8 isolate runtime using **Hono TypeScript**, interfacing directly with Supabase, Gemini AI, OpenRouteService, and Mapbox.

---

## Architectural Topology

```
                  ┌───────────────────────────────┐
                  │    Users (Web, iOS, Android)  │
                  └──────────────┬────────────────┘
                                 │
                 ┌───────────────┴───────────────┐
                 │                               │
                 ▼                               ▼
       https://voyplan.in              https://api.voyplan.in
    (Cloudflare Pages Frontend)     (Cloudflare Worker Backend)
                                                 │
                     ┌───────────────────────────┼───────────────────────────┐
                     ▼                           ▼                           ▼
            Supabase PostgreSQL             Google Gemini             Mapbox / ORS
           (Auth, Database, RLS)         (AI Trip Generation)      (Routing & Directions)
```

---

## Key Benefits Over Previous Hosting
1. **Zero Bandwidth Costs & No Workspace Suspensions**: Built on Cloudflare Workers edge architecture without Render Hobby bandwidth limits.
2. **Global Low-Latency Execution**: Requests terminate at the closest Cloudflare edge location worldwide with cold starts < 5ms.
3. **100% Contract Preservation**: Exact match for all endpoints, JSON structures, error shapes, status codes, and HTTP headers.
4. **Resilient Failover**: `backend/` and `render.yaml` remain intact in the codebase as an operational hot standby / rollback target.

---

## Directory Structure
```
cloudflare-worker/
├── package.json              # Dependencies: Hono, @supabase/supabase-js, Vitest, Wrangler
├── tsconfig.json             # TypeScript configuration for Workers V8 runtime
├── wrangler.jsonc            # Cloudflare Worker configuration & route bindings
├── .dev.vars.example         # Template for local development secrets
├── src/
│   ├── index.ts              # Worker entrypoint, middlewares, and route registration
│   ├── types/
│   │   └── env.ts            # Typed Cloudflare Worker Bindings & Variables
│   ├── middleware/
│   │   ├── auth.ts           # Supabase Bearer token verification & user context injection
│   │   ├── cors.ts           # Dynamic origin CORS with credentials support
│   │   ├── rateLimit.ts      # Edge sliding-window rate limiters (Global + AI burst)
│   │   ├── security.ts       # OWASP security headers (HSTS, nosniff, frame protection)
│   │   └── telemetry.ts      # Request timing, structured JSON logging, APM metrics
│   ├── routes/
│   │   ├── health.ts         # GET /health, GET /ready (readiness probe)
│   │   ├── status.ts         # GET /status (APM UI), GET /api/metrics
│   │   ├── trip.ts           # POST /api/trip/calculate-route, /optimize-stops
│   │   ├── ai.ts             # POST /api/ai/plan-trip, /itinerary, /recommend, /ask
│   │   ├── account.ts        # GET /api/account/profile, /export, /delete
│   │   ├── vehicles.ts       # GET /api/vehicles/brands, /models, /search, /image
│   │   ├── fuel.ts           # GET /api/fuel/prices, POST /api/fuel/calculate
│   │   ├── treks.ts          # GET /api/treks, GET /api/treks/geometry
│   │   ├── geocode.ts        # GET /api/geocode, /reverse, /autocomplete
│   │   ├── currency.ts       # GET /api/currency/rates
│   │   └── prices.ts         # GET /api/prices/tolls, /estimates
│   ├── services/             # 25 ported services using fetch-only ES Modules
│   └── utils/                # Geographic calculations, Haversine, Polyline decoding
└── test/
    └── api.test.ts           # 21 automated integration tests run via Vitest
```

---

## API Endpoints Summary

| Endpoint | Method | Auth | Description |
| :--- | :--- | :--- | :--- |
| `/health` | GET | Public | Service health metadata & version |
| `/ready` | GET | Public | Database & dependency readiness probe |
| `/status` | GET | Public | Real-time APM monitoring dashboard HTML |
| `/api/metrics` | GET | Public | Structured APM telemetry and metrics JSON |
| `/api/trip/calculate-route` | POST | Public | Turn-by-turn route, fuel cost, and tolls |
| `/api/trip/optimize-stops` | POST | Public | TSP waypoint route optimizer |
| `/api/vehicles/brands` | GET | Public | Vehicle brand directory |
| `/api/vehicles/models` | GET | Public | Models for a specified brand |
| `/api/vehicles/search` | GET | Public | Vehicle query search |
| `/api/fuel/prices` | GET | Public | Regional real-time fuel and EV prices |
| `/api/treks` | GET | Public | Nearby treks with trail geometry |
| `/api/currency/rates` | GET | Public | Foreign currency exchange rates |
| `/api/ai/status` | GET | Public | AI engine & model provider status |
| `/api/ai/itinerary` | POST | Public | AI itinerary generator (Gemini 2.5) |
| `/api/ai/ask` | POST | Public | Contextual AI travel assistant chat |
| `/api/account/profile` | GET | Protected | Authenticated user profile and trips |
| `/api/account/export` | GET | Protected | GDPR user data export |
| `/api/account/delete` | DELETE | Protected | Account deletion |

---

## Local Development

### 1. Install Dependencies
```bash
cd cloudflare-worker
npm install
```

### 2. Configure Environment Variables
Copy `.dev.vars.example` to `.dev.vars` in the `cloudflare-worker` folder:
```bash
cp .dev.vars.example .dev.vars
```
Fill in the API keys for Supabase, Gemini, Mapbox, and OpenRouteService.

### 3. Run Locally with Wrangler
```bash
npm run dev
```
The Worker API will be available at `http://localhost:8787`.

### 4. Run Automated Tests
```bash
npm test
```

### 5. Typecheck
```bash
npm run build
```

---

## Secret Configuration on Cloudflare

Set sensitive production secrets in Cloudflare Workers using Wrangler:
```bash
npx wrangler secret put SUPABASE_URL
npx wrangler secret put SUPABASE_ANON_KEY
npx wrangler secret put SUPABASE_SERVICE_ROLE_KEY
npx wrangler secret put GEMINI_API_KEY
npx wrangler secret put MAPBOX_TOKEN
npx wrangler secret put OPENROUTE_SERVICE_API_KEY
```

---

## CI/CD Deployment Workflow

The GitHub Actions workflow `.github/workflows/cloudflare-worker.yml` automates the release process:
- **On Pull Requests**: Runs TypeScript typecheck (`npm run build`), Vitest suite (`npm test`), and bundle dry-run (`wrangler deploy --dry-run`).
- **On Push to `main` or Tag `v*`**: Deploys the worker directly to Cloudflare Workers via `cloudflare/wrangler-action@v3`.
- **Manual Trigger**: Can be dispatched manually from the Actions tab with a single click.

---

## Rollback Procedure to Render (if needed)

In the unlikely event that a rollback to Render is necessary:
1. In Cloudflare DNS, update the CNAME record for `api.voyplan.in` to point to the Render backend service domain (e.g. `voyplan-backend.onrender.com`).
2. Alternatively, deploy the Flutter Web frontend with `--dart-define=BACKEND_URL=https://voyplan-backend.onrender.com`.
3. The `backend/` directory and `render.yaml` remain unmodified and fully operational.
