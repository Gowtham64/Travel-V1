# VoyPlan Technical Implementation Plan

This document outlines the implementation of security hardening, performance optimizations, and the deployment roadmap for VoyPlan.

## 🎯 Objectives
- **Zero Cost**: Maintain 100% free-tier operations.
- **Maximum Speed**: Eliminate lag in AI itinerary generation.
- **Global Accuracy**: Ensure routing and planning work across all countries.
- **Enterprise Security**: Prevent API abuse and prompt injection.

---

## 🛠️ Phase 1: Security & Cost Hardening (Completed)
*Implemented to prevent unexpected costs and unauthorized access.*

### 1.1 AI Endpoint Protection
- **Action**: Integrated `requireAuth` middleware into the `aiRouter`.
- **Impact**: All AI services (`/recommend`, `/itinerary`, `/ask`) now require a valid Supabase JWT.
- **Benefit**: Prevents anonymous users/bots from consuming AI tokens.

### 1.2 Distributed Rate Limiting
- **Action**: Migrated `generalRateLimiter` and `aiRateLimiter` from in-memory `Map` to **Cloudflare KV**.
- **Impact**: Limits are now global across all edge isolates.
- **Benefit**: Stops API abuse and protects free-tier quotas.

### 1.3 Prompt Injection Defense
- **Action**: Created `sanitizeInput` utility and wrapped AI inputs in structural delimiters (`###START###` / `###END###`).
- **Impact**: AI can now distinguish between system instructions and user data.
- **Benefit**: Prevents "jailbreaking" and unauthorized prompt manipulation.

---

## ⚡ Phase 2: Performance & Global Scaling (Completed)
*Implemented to remove lag and ensure global routing accuracy.*

### 2.1 Parallel Data Fetching
- **Action**: Replaced sequential `await` calls with `Promise.all()` for location resolutions.
- **Impact**: User-specified places are resolved simultaneously.
- **Benefit**: Significant reduction in "Time to First Byte" (TTFB).

### 2.2 Pre-emptive Geocoding
- **Action**: Triggered destination geocoding immediately upon request receipt, rather than waiting for the AI plan to finish.
- **Impact**: The budget and internationalization check start instantly.
- **Benefit**: Removes one full network round-trip from the critical path.

### 2.3 Balanced Itinerary Distribution
- **Action**: Upgraded the stop partitioning logic to use a "Smoother Distribution" algorithm.
- **Impact**: Sights are spread evenly across days, avoiding "clumped" schedules.
- **Benefit**: More realistic and user-friendly itineraries.

### 2.4 Multi-Provider Routing
- **Action**: Reinforced the routing fallback chain (**Mapbox $\rightarrow$ ORS $\rightarrow$ OSRM**).
- **Impact**: The system automatically switches to the most reliable provider for the specific region.
- **Benefit**: 100% routing coverage globally.

---

## 🚀 Phase 3: Production Deployment (Action Required)
*Follow these steps to push changes to `voyplan.in`.*

### Step 1: Cloudflare KV Setup (CRITICAL)
The new rate limiter requires a KV namespace.
1. Go to **Cloudflare Dashboard $\rightarrow$ Workers & Pages $\rightarrow$ KV**.
2. Create a namespace named `RATE_LIMIT_KV`.
3. Go to your **Worker (`voyplan-api`) $\rightarrow$ Settings $\rightarrow$ Variables**.
4. Bind the `RATE_LIMIT_KV` variable to the namespace you just created.

### Step 2: Deployment Pipeline
1. Merge the current branch into `main`.
2. GitHub Actions will trigger the `deploy-production.yml` workflow.
3. Verify the Worker is deployed via `https://api.voyplan.in/health`.

### Step 3: Final Verification
- Run `./scripts/health-check.sh https://api.voyplan.in`.
- Run `./scripts/smoke-test.sh https://voyplan.in https://api.voyplan.in`.
- Verify a "Smart Itinerary" can be generated without lag.

---

## 🗺️ Phase 4: Future Roadmap (Recommendations)
*Suggested improvements for the next development cycle.*

### 1. Client-Side Caching (Mobile)
Implement a local SQLite or Hive cache in the Flutter app for previously resolved locations and routes to reduce API calls.

### 2. AI-Human Hybrid Feedback
Add a "Correct this stop" feature where users can manually swap stops, and the AI learns from these corrections for future plans.

### 3. Collaborative Planning
Enable real-time collaborative trip editing using Supabase Realtime, allowing multiple users to build one itinerary.

### 4. Dynamic Speed Profiles
Introduce "Road Condition" offsets based on the country (e.g., slower average speeds for rural India vs. German Autobahns).
