# VoyPlan — Environments & Release Workflow

Three isolated environments. **Production (`voyplan.in`) is never touched by
development** — new work flows `feature/* → develop → staging → main → prod`.

| Env | URL | Branch | Supabase | Backend | Host |
|-----|-----|--------|----------|---------|------|
| **Development** | local | `feature/*` | staging (or local) | `localhost:3000` | local |
| **Staging** | `staging.voyplan.in` | `develop` | **staging project** | staging Render service | Cloudflare Pages |
| **Production** | `voyplan.in` | `main` | prod project (`dtemayjpttktntooxraa`) | `api.voyplan.in` → Render | Cloudflare Pages |

## Git flow
```
feature/xyz ──PR──▶ develop ──auto──▶ staging.voyplan.in ──QA──▶ PR ──▶ main ──manual approve──▶ voyplan.in
```
- `main` is protected: no direct pushes, PR + passing CI required.
- Never commit directly to `main`.

## How environments are selected (no code edits needed)
The app is environment-agnostic in source; values come from `--dart-define`
(see `mobile/lib/config/app_config.dart`). **Defaults are production**, so a
plain build is production. Staging overrides via defines:
```
--dart-define=APP_ENV=staging
--dart-define=SUPABASE_URL=https://<staging-ref>.supabase.co
--dart-define=SUPABASE_ANON_KEY=<staging anon key>
--dart-define=BACKEND_URL=https://<staging-backend>.onrender.com
--dart-define=MAPBOX_TOKEN=pk.xxx
```
Staging builds show an unmissable **⚠ STAGING — NOT PRODUCTION** banner; prod never does.

## CI/CD (.github/workflows)
- `ci.yml` — PR into develop/main: Flutter analyze + test + web build, backend install + test. Make it a **required status check** on `main` and `develop`.
- `deploy-staging.yml` — push to `develop` → build (staging config) → Cloudflare Pages. Inert until staging secrets exist.
- `deploy-production.yml` — **manual only** (Actions → Run workflow, type `DEPLOY`) or a `v*` tag → build (prod config) → Cloudflare Pages. `deploy_web.sh` is the equivalent explicit/local path.

---

## ⛳ One-time setup you must do (accounts I can't create)

### 1. Staging Supabase project
- supabase.com → New project `voyplan-staging` (free).
- SQL Editor → run, in order, the repo's schema files so staging mirrors prod:
  `backend/supabase_schema.sql`, `backend/profile_schema.sql`,
  `backend/supabase/*.sql`, `backend/supabase/cross_device_trip_sync.sql`.
- Auth → enable Email + Google (a **separate** OAuth client for staging), keep "Confirm email" ON.
- Copy the staging **Project URL** and **anon/publishable key**.

### 2. Staging backend (Render)
- New Web Service from the same repo, branch `develop`, root `backend`, start `node src/index.js`.
- Env vars from `backend/.env.staging.example` (staging Supabase URL/key + keys).
- Copy the service URL (e.g. `https://voyplan-staging.onrender.com`).

### 3. Cloudflare Pages (production, staging host + PR previews)
- Cloudflare → Pages → Create project `voyplan-staging` (Direct Upload / connect repo).
- Create or select the production Pages project; its exact project name is required as `CLOUDFLARE_PROJECT_NAME`.
- Get **Account ID** and create an **API token** (Pages:Edit).

### 4. GitHub secrets (Settings → Secrets → Actions)
```
MAPBOX_TOKEN                = pk.your_url_restricted_token
CLOUDFLARE_API_TOKEN        = <cloudflare token>
CLOUDFLARE_ACCOUNT_ID       = <cloudflare account id>
CLOUDFLARE_PROJECT_NAME     = <production Pages project name>
CLOUDFLARE_STAGING_PROJECT_NAME = <staging Pages project name>
STAGING_SUPABASE_URL        = https://<staging-ref>.supabase.co
STAGING_SUPABASE_ANON_KEY   = <staging anon key>
STAGING_BACKEND_URL         = https://<staging-backend>.onrender.com
```

### 5. DNS (manual dashboard action)
- `CNAME staging → voyplan-staging.pages.dev` (Cloudflare Pages target).
- Add `voyplan.in` and `www.voyplan.in` as custom domains on the production Pages project.
- Add `api.voyplan.in` as a custom domain on the existing Render Node service. Copy the
  exact Render hostname from that service's dashboard; do not infer or replace it here.
- At the DNS provider, point `api` to the Render custom-domain target/record shown by
  Render. Complete the custom-domain verification in both dashboards.

---

## Release process (steady state)
1. `git checkout develop && git pull`
2. `git checkout -b feature/xyz` — build the feature.
3. Push → open PR into `develop`. CI must pass.
4. Merge → auto-deploys to `staging.voyplan.in`. QA there.
5. Fix on the feature branch, repeat until stable.
6. Open PR `develop → main`. Review + CI pass.
7. Merge to `main`, then **Actions → Deploy Production → Run workflow → type `DEPLOY`**.
8. Smoke-test `voyplan.in`. If broken, **rollback** (below).

## Rollback
- **Web:** Re-run the last known-good Cloudflare Pages workflow build, or `git revert` the bad merge on `main` and re-run the production workflow.
- **DB:** Supabase → Database → Backups (prod). Always back up before a prod migration.

## Database safety (prod migrations)
Test migration locally → on staging → back up prod (Supabase backup) → apply to
prod → verify → keep the down/rollback SQL ready. Never run `DROP`/`TRUNCATE`/
unscoped `DELETE` on prod without a backup.

## Mobile — Android flavors
Three flavors install **side-by-side** (distinct applicationId + app name), so a
staging/dev app can never be mistaken for production:

| Flavor | applicationId | App name |
|--------|---------------|----------|
| prod | `io.github.gowtham64.travelapp` | Voyplan |
| staging | `io.github.gowtham64.travelapp.staging` | Voyplan Staging |
| dev | `io.github.gowtham64.travelapp.dev` | Voyplan Dev |

The environment each build talks to comes from `--dart-define`, so a staging build
physically cannot reach production. Build commands:
```bash
# Production
flutter build apk --release --flavor prod \
  --dart-define=APP_ENV=production --dart-define=MAPBOX_TOKEN=pk.xxx

# Staging (points at staging Supabase + backend, shows STAGING banner)
flutter build apk --release --flavor staging \
  --dart-define=APP_ENV=staging \
  --dart-define=SUPABASE_URL=https://fptqaasbzlioohvpyfht.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<staging anon key> \
  --dart-define=BACKEND_URL=https://voyplan-staging.onrender.com \
  --dart-define=MAPBOX_TOKEN=pk.xxx

# Dev (local backend) — run on a device/emulator
flutter run --flavor dev --dart-define=APP_ENV=development
```
Any Android build/run now REQUIRES `--flavor`. Firebase Analytics is wired to the
prod flavor; staging/dev carry placeholder Firebase configs (no reporting) — to
get real staging analytics, register `…​.staging` as an app in the Firebase
project and drop its `google-services.json` into `android/app/src/staging/`.

iOS stays a single target (free Apple team = dev installs only) until enrolled in
the Apple Developer Program; build iOS with the matching `--dart-define`s (no
`--flavor`).
