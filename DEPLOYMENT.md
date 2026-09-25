# VoyPlan Production Deployment

Production is deployed only from `main` by `.github/workflows/deploy-production.yml`.

## Required Cloudflare configuration

- Cloudflare Pages project: `voyplan`, with `voyplan.in` (and optionally `www.voyplan.in`) attached.
- Cloudflare Worker: `voyplan-api`, routed to `api.voyplan.in/*` as declared in `cloudflare-worker/wrangler.jsonc`.
- GitHub Actions secrets: `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, and `MAPBOX_TOKEN`.
- Worker secrets configured in Cloudflare; see [ENVIRONMENT.md](ENVIRONMENT.md).

The Pages project name is the committed workflow variable `PAGES_PROJECT=voyplan`; it is intentionally not a secret.

## Pre-deployment checks

```bash
cd cloudflare-worker && npm ci && npm run build && npm test && npx wrangler deploy --dry-run
cd ../mobile && flutter pub get && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test
flutter build web --release --dart-define=APP_ENV=production --dart-define=BACKEND_URL=https://api.voyplan.in
```

## Pipeline

On a push to `main`, the workflow:

1. Validates Cloudflare credentials.
2. Deploys `cloudflare-worker/` with its locked Wrangler version.
3. Requires `https://api.voyplan.in/health` to return successfully.
4. Builds `mobile/` for production and copies the Pages headers and SPA redirects.
5. Confirms the `voyplan` Pages project, deploys the build, and verifies `https://voyplan.in/`.

Use **Actions → Deploy Production (Cloudflare Worker + Pages) → Run workflow** and type `DEPLOY` when an explicit manual run is needed.

## Post-deployment verification

```bash
./scripts/health-check.sh https://api.voyplan.in
./scripts/smoke-test.sh https://voyplan.in https://api.voyplan.in
```

Confirm that `/` and `/health` return HTTP 200, `/login` redirects to
`/app/?auth=login`, and authenticated trip creation works from `voyplan.in`.

## Mobile builds

`.github/workflows/mobile-build.yml` builds the `prod` Android flavor on `main` and publishes `app-prod-release.apk` to the rolling `android-latest` release. Its macOS job compiles the unsigned iOS simulator app. Native store distribution remains a separately signed release process.
