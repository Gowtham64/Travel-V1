# VoyPlan Environment Variables Reference

## 1. Overview & Security Rules

All configuration in VoyPlan is environment-aware and driven by 12-factor principles.
- **Never commit `.env` files, API keys, or JWT secrets to Git.**
- Secrets are injected via **GitHub Secrets**, **Render Environment Variables**, or **Cloudflare Pages Environment Variables**.
- Public/client tokens (e.g. Supabase Anon Key, Mapbox public tokens) must be restricted by domain or bundle identifier.

---

## 2. Backend API Service (`voyplan-backend`)

Configured in the **Render Dashboard → Environment** for service `voyplan-backend`:

| Variable Name | Required | Secret? | Production Value / Description |
|---|---|---|---|
| `NODE_ENV` | Yes | No | `production` |
| `PORT` | Yes | No | `3000` (assigned automatically by Render or defaults to 3000) |
| `ALLOWED_ORIGINS` | Yes | No | `https://voyplan.in,https://www.voyplan.in,https://*.pages.dev` |
| `SUPABASE_URL` | Yes | No | `https://dtemayjpttktntooxraa.supabase.co` |
| `SUPABASE_ANON_KEY` | Yes | No | Supabase anonymous public key |
| `SUPABASE_SERVICE_ROLE_KEY` | Yes | **YES** | Supabase service role key (bypasses RLS for backend batch tasks) |
| `SUPABASE_JWT_SECRET` | Yes | **YES** | Supabase JWT secret used to cryptographically verify user tokens |
| `MAPBOX_ACCESS_TOKEN` | Yes | **YES** | Mapbox secret token for server-side matrix and routing calls |
| `TOLLGURU_API_KEY` | Optional | **YES** | API key for toll rate calculations |
| `GEMINI_API_KEY` | Optional | **YES** | Google AI Studio key for AI itinerary generation fallback |

---

## 3. Flutter Web Frontend & Mobile Client

Configured via Flutter compile-time definitions (`--dart-define`):

| Define Name | Required | Secret? | Production Default | Description |
|---|---|---|---|---|
| `APP_ENV` | Yes | No | `production` | Environment profile (`production`, `staging`, `development`) |
| `BACKEND_URL` | Yes | No | `https://api.voyplan.in` | Canonical HTTPS URL of the Express backend |
| `MAPBOX_TOKEN` | Yes | No | Client-safe public token | Mapbox map tile and client search access token |
| `SUPABASE_URL` | Yes | No | `https://dtemayjpttktntooxraa.supabase.co` | Supabase endpoint |
| `SUPABASE_ANON_KEY` | Yes | No | `sb_publishable_...` | Supabase public client anon key |

---

## 4. GitHub Actions CI/CD Secrets

Configured in **GitHub Repository → Settings → Secrets and variables → Actions**:

| Secret Name | Required By | Description |
|---|---|---|
| `CLOUDFLARE_API_TOKEN` | `deploy-production.yml`, `deploy-staging.yml` | Cloudflare API token with Pages Edit permission |
| `CLOUDFLARE_ACCOUNT_ID` | `deploy-production.yml`, `deploy-staging.yml` | Cloudflare Account ID |
| `CLOUDFLARE_PROJECT_NAME` | `deploy-production.yml` | Cloudflare Pages project name (e.g., `voyplan`) |
| `MAPBOX_TOKEN` | `ci.yml`, `mobile-build.yml` | Mapbox token for Flutter test and web builds |
| `RENDER_API_KEY` | Render deployment webhooks | Render API token if triggering webhook deploys |

---

## 5. Verification Command

To verify that your current terminal or CI environment has valid non-localhost configurations:

```bash
./scripts/validate-env.sh production
```
