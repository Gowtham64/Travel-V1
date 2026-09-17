# Cloudflare Pages deployment

## Production configuration

The canonical deployment is `.github/workflows/deploy-production.yml`:

- Trigger: manual workflow with `DEPLOY`, or a version tag `v*`.
- Flutter command: `flutter build web --release --base-href "/"`.
- Production defines: `APP_ENV=production`, `BACKEND_URL=https://api.voyplan.in`,
  and the public URL-restricted `MAPBOX_TOKEN`.
- Output directory: `mobile/build/web`.
- Publish command: Wrangler Pages deploy using the project name stored in the
  `CLOUDFLARE_PROJECT_NAME` GitHub secret.

The local `deploy_web.sh` entry point uses the same build helper. By default it
only builds; setting `DEPLOY_CLOUDFLARE=1` explicitly enables Wrangler upload.
It no longer force-pushes `gh-pages`.

For Cloudflare dashboard/Git integration, use the same Flutter build and copy
`cloudflare/_headers` and `cloudflare/_redirects` into the output directory.
Because Flutter is in a monorepo, the GitHub Actions + Wrangler path is the
recommended canonical path unless the Pages build image is configured with the
required Flutter SDK.

## Required GitHub secrets

```text
CLOUDFLARE_API_TOKEN       Pages:Edit token for the account
CLOUDFLARE_ACCOUNT_ID      Cloudflare account ID
CLOUDFLARE_PROJECT_NAME    production Pages project name
MAPBOX_TOKEN               public URL-restricted browser token
```

Staging additionally uses:

```text
CLOUDFLARE_STAGING_PROJECT_NAME
STAGING_SUPABASE_URL
STAGING_SUPABASE_ANON_KEY
STAGING_BACKEND_URL
```

Do not put Render provider secrets, Supabase service-role keys, or AI keys in
Cloudflare Pages variables or Flutter `--dart-define`s.

## Headers and service worker

`cloudflare/_headers` applies only to Pages static assets:

- `index.html`, Flutter bootstrap/runtime, `main.dart.js`, `version.json`, and
  `flutter_service_worker.js` are no-store/no-cache so a new deployment can be
  discovered.
- CanvasKit files use long-lived immutable caching.
- Flutter application assets use a bounded one-day cache with revalidation.
- API responses are not cached by Pages.

Flutter's generated `flutter_service_worker.js` is the single service-worker
owner. The old extra `pwa_sw.js` registration was removed from the source HTML;
this avoids two workers competing for the same scope. Do not replace the
generated worker with a kill-switch during deployment. Verify a new build in a
fresh/incognito browser and after a normal reload.

`cloudflare/_redirects` provides the Flutter SPA fallback and redirects the old
`/app` and `/app/` entry points to the new root. Static files take precedence
over the fallback; test direct refreshes on any client-side route.

## Custom domains and DNS — MANUAL ACTION REQUIRED

No Cloudflare, DNS, or Render dashboard change has been performed by this
repository migration.

1. Create/select the production Pages project and deploy one successful build.
2. In Pages → Custom domains, associate `voyplan.in` and `www.voyplan.in` with
   that production project. For an apex domain, Cloudflare requires the domain
   zone/nameservers to be managed by Cloudflare.
3. In the existing Render Node service, add the custom domain `api.voyplan.in`.
4. Copy the exact target/verification record shown by Render into the DNS
   provider. Do not guess the Render hostname.
5. Wait for TLS/custom-domain verification, then test `https://api.voyplan.in/health`.
6. Add `https://voyplan.in` and `https://www.voyplan.in` to the Render
   `ALLOWED_ORIGINS` value. Add `https://staging.voyplan.in` only if the
   production API is intentionally used by staging QA.

## Local and staging builds

```bash
# local backend
cd backend && npm run dev

# Flutter local build/run
cd mobile
flutter run --dart-define=APP_ENV=development \
  --dart-define=BACKEND_URL=http://localhost:3000

# staging example
flutter build web --release --base-href "/" \
  --dart-define=APP_ENV=staging \
  --dart-define=BACKEND_URL=https://staging-api.voyplan.in \
  --dart-define=SUPABASE_URL=https://<staging-ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<staging-publishable-key>
```

The staging custom API hostname is a required setup value; it is not currently
invented or hard-coded by this repository.

## Backend caching and bandwidth controls

The Express API now enables thresholded compression. Safe public GET responses
for vehicle catalog data, prices, currency data, and vehicle images advertise
bounded caching; personalized account/trip/auth/AI operations remain uncached.
Express ETags remain enabled for eligible responses. The lightweight metrics
endpoint reports endpoint hits and response bytes without recording tokens,
authorization headers, or private payloads.

Maps use direct browser/provider access where supported by the existing client;
map tiles are not served by Express. AI remains `Flutter → Render /api/ai →
Gemini`, so provider credentials never enter the web bundle.

## Verification checklist

- Build output contains root `index.html`, `flutter_bootstrap.js`, CanvasKit,
  assets, and the generated Flutter service worker.
- `index.html` uses `<base href="/">`.
- `main.dart.js` contains `https://api.voyplan.in`, not the generated Render
  hostname.
- Browser Network shows static files from Pages and API calls from
  `api.voyplan.in`.
- Test guest/authenticated login, logout, one-way trip, around trip, maps,
  vehicles/images, saved trips/places, AI, direct refresh, and `/app/` legacy
  redirect.
- Confirm response `Content-Encoding` for a large JSON response and inspect
  `/api/metrics` for the largest endpoint byte counters.

## Troubleshooting

- A 522/custom-domain error usually means the Pages domain was not associated
  in the Pages dashboard before the DNS record was added.
- A stale app after release indicates a service-worker or header problem; check
  `flutter_service_worker.js` and `index.html` cache headers before clearing
  user data.
- CORS failures mean the exact browser origin is missing from Render's
  `ALLOWED_ORIGINS`; never solve this by enabling `*` for authenticated APIs.
- A failing API alias means the Render custom domain/DNS/TLS setup is incomplete;
  keep using the dashboard-provided target during verification.
