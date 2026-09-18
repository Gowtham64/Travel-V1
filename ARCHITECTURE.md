# VoyPlan Architecture Documentation

## 1. System Overview

VoyPlan is an end-to-end intelligent road trip and itinerary planning platform consisting of:
- **Frontend SPA**: Flutter Web application served globally via Cloudflare Pages edge network (`https://voyplan.in`).
- **Mobile Native Applications**: Flutter codebase compiled for Android (APK/AAB) and iOS (`Runner.app` / IPA).
- **Backend API**: Node.js / Express microservice deployed on Render (`https://api.voyplan.in` or `voyplan-backend`).
- **Database & Authentication**: Supabase Postgres with Row Level Security (RLS) and GoTrue Auth (`https://dtemayjpttktntooxraa.supabase.co`).
- **AI & Optimization Services**: Python AI Engineering service (`voyplan-ai-engineering` on Render) providing LLM-assisted trip recommendations, route optimization, and day planning.
- **External Services**: Mapbox Navigation / Geocoding APIs, OpenStreetMap / OSRM routing, TollGuru, and live fuel price APIs.

```mermaid
flowchart TD
    subgraph Clients
        WebClient["Web Browser (https://voyplan.in)"]
        MobileAndroid["Android App (APK / AAB)"]
        MobileiOS["iOS App (Runner.app / IPA)"]
    end

    subgraph CDN_and_Hosting["Edge & Hosting Layer"]
        CFPages["Cloudflare Pages (voyplan.in)<br/>• Serves Flutter Web SPA<br/>• Edge Caching & Security Headers<br/>• /* -> /index.html 200 Rewrite"]
    end

    subgraph Backend_Services["Application Backend (Render)"]
        NodeAPI["voyplan-backend (Express / Node 20)<br/>• /health (Liveness)<br/>• /ready (Readiness & DB Check)<br/>• /api/trips, /api/vehicles, /api/fuel"]
        AIService["voyplan-ai-engineering (Python FastApi / Uvicorn)<br/>• Smart Itineraries & LLM Generation"]
    end

    subgraph Cloud_Data["Persistence & Auth (Supabase)"]
        SupaAuth["Supabase GoTrue Auth<br/>• JWT Access & Refresh Tokens<br/>• OAuth & Password Auth"]
        SupaDB["PostgreSQL Database<br/>• Tables: trips, user_details, shared_trips<br/>• Row Level Security (RLS)"]
    end

    subgraph External_APIs["External Services"]
        MapboxAPI["Mapbox APIs (Tiles, Navigation, Geocoding)"]
        FuelTollAPIs["Fuel Price & TollGuru APIs"]
    end

    WebClient --> CFPages
    CFPages --> NodeAPI
    MobileAndroid --> NodeAPI
    MobileiOS --> NodeAPI

    WebClient --> SupaAuth
    MobileAndroid --> SupaAuth
    MobileiOS --> SupaAuth

    NodeAPI --> SupaDB
    NodeAPI --> AIService
    NodeAPI --> External_APIs
    AIService --> SupaDB
```

---

## 2. Infrastructure & Topology

| Component | Provider | URL / Endpoint | Purpose |
|---|---|---|---|
| **Web Frontend** | Cloudflare Pages | `https://voyplan.in` | Global CDN hosting Flutter Web SPA (`mobile/build/web`) |
| **Backend API** | Render Web Service | `https://api.voyplan.in` | Express API, auth verification, fuel, vehicles, metrics |
| **AI Engineering** | Render Web Service | Private/Internal | LLM itinerary generation and trip recommendations |
| **Database & Auth** | Supabase Cloud | `https://dtemayjpttktntooxraa.supabase.co` | PostgreSQL with RLS, GoTrue authentication engine |
| **DNS Management** | Cloudflare DNS | `voyplan.in`, `api.voyplan.in` | DNSSEC, SSL Termination, edge routing |
| **CI / CD** | GitHub Actions | Workflows in `.github/workflows/` | PR verification, mobile APK artifacts, production deployment |

---

## 3. Data Flow & Authentication Lifecycle

1. **User Authentication**:
   - The client invokes `Supabase.instance.client.auth.signInWithPassword()` directly to Supabase Auth over HTTPS.
   - Upon authentication, Supabase returns a JSON Web Token (`access_token`) and a long-lived `refresh_token`.
   - The Flutter client securely persists the session using platform storage (`SharedPreferences` on mobile, `localStorage` on web).

2. **API Requests**:
   - Client attaches the token in the HTTP Authorization header: `Authorization: Bearer <access_token>`.
   - The backend API (`backend/src/middleware/auth.js`) verifies the JWT against `SUPABASE_JWT_SECRET` using HMAC-SHA256.
   - If valid, `req.user` is populated with `user_id` and role; otherwise, HTTP 401 is returned.

3. **Database Queries**:
   - Direct client queries to Supabase Postgres leverage Postgres RLS policies based on `auth.uid() = user_id`.
   - Backend queries use service role keys or user-delegated tokens to ensure data segregation.

---

## 4. Reliability & Health Probes

- **Liveness Probe**: `GET /health` returns `{ "status": "ok", "version": "2.4.0", "timestamp": ... }` within < 100ms.
- **Readiness Probe**: `GET /ready` actively verifies:
  - Database connectivity to Supabase.
  - Presence of essential environment configurations (`SUPABASE_URL`, `SUPABASE_ANON_KEY`).
  - Returns HTTP 200 `{ "status": "ready", ... }` or HTTP 503 `{ "status": "degraded", ... }`.
