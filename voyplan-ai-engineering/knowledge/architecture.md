# VoyPlan System Architecture

## 1. High-Level Architecture Overview

VoyPlan is an AI-powered multi-modal travel planning and route optimization application. It serves one-way road trips, AI round trips, time-blocked itineraries, real-time routing, fuel/toll/hotel budgets, and active "today" trip execution across Web, Android, and iOS.

```
┌────────────────────────────────────────────────────────┐
│                   CLIENT SURFACES                      │
│  Flutter Web (/app)  │  Android (APK/AAB)  │  iOS App  │
│          Landing & Install Portals (HTML5/JS)          │
└───────────────────────────┬────────────────────────────┘
                            │ HTTPS / WSS
┌───────────────────────────▼────────────────────────────┐
│                  BACKEND REST & WS API                 │
│         Node.js 20 + Express 4.19.2 + 'ws' 8.21        │
│    Helmet Security • Express Rate Limiter • CORS       │
└──────┬──────────────┬─────────────┬─────────────┬──────┘
       │              │             │             │
┌──────▼──────┐┌──────▼──────┐┌─────▼─────┐┌──────▼──────┐
│  AI ENGINE  ││   ROUTING   ││ GEOCODING ││  DATABASE   │
│  Gemini API ││ OSRM Public ││  Mapbox   ││  Supabase   │
│ Groq/Llama  ││   Mapbox    ││   Pelias  ││ PostgreSQL  │
│  OpenRouter ││     ORS     ││ Nominatim ││  Auth+Data  │
└─────────────┘└─────────────┘└───────────┘└─────────────┘
```

## 2. Component Hierarchy
1. **Frontend (`mobile/`)**: Flutter multi-platform application utilizing Dart 3. Supports responsive web, desktop, and mobile form factors with shared state management (`provider`).
2. **Landing & Documentation (`web/`)**: Vanilla HTML5/CSS3 landing site, PWA manifest, Apple install guide, and SideStore application repository.
3. **Backend (`backend/src/`)**: Express REST endpoints and WebSocket server.
4. **Autonomous AI Engineering System (`voyplan-ai-engineering/`)**: 24/7 multi-agent autonomous engineering team running R&D, development, testing, QA, and release.

## 3. Environments & Hosting Infrastructure
- **Production (`voyplan.in`)**:
  - Web Client: GitHub Pages (`gh-pages` branch) deployed from `./public` (landing + `/app/`).
  - Backend: Render Web Service (`travel-v1-mzia.onrender.com`).
  - Database: Supabase Prod project (`dtemayjpttktntooxraa`).
- **Staging (`staging.voyplan.in`)**:
  - Web Client: Cloudflare Pages deployed from `develop` branch.
  - Backend: Render Staging Web Service.
  - Database: Supabase Staging project (`voyplan-staging`).
- **Development (Local)**:
  - Backend: `localhost:3000`
  - Client: `localhost:8080` (or Flutter run)
  - AI Dashboard: `localhost:3050`
