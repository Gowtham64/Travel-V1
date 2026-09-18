# VoyPlan Production Deployment Guide

## 1. Pre-Deployment Verification

Before triggering any production build or deployment, run the automated environment validator:

```bash
# Validate production environment
./scripts/validate-env.sh production
```

This ensures:
- No `localhost` references in `BACKEND_URL` or `SUPABASE_URL`.
- Landing page and auth wrapper loop-guards are active.
- Security headers in `cloudflare/_headers` are intact.

---

## 2. Frontend Deployment (Cloudflare Pages)

VoyPlan's production web frontend is hosted on Cloudflare Pages serving `https://voyplan.in`.

### Automated Deployment (GitHub Actions)
Trigger the production workflow via GitHub Actions:
1. Navigate to **GitHub Repository → Actions → Deploy Production**.
2. Click **Run workflow**, choose branch `main`.
3. In the confirmation box, type `DEPLOY` and submit.
4. The workflow will:
   - Run `flutter build web --release --base-href "/" --dart-define=APP_ENV=production --dart-define=BACKEND_URL=https://api.voyplan.in`.
   - Copy `cloudflare/_headers` and `cloudflare/_redirects`.
   - Deploy directly to Cloudflare Pages via Wrangler.

### Manual / Local Build & Deploy
If deploying via CLI with Wrangler:
```bash
# 1. Build the production web bundle
./scripts/build_cloudflare_pages.sh

# 2. Deploy using Wrangler
npx wrangler pages deploy mobile/build/web --project-name=voyplan
```

### Cloudflare Pages Routing & Header Rules
- `cloudflare/_redirects`:
  - `/app/* -> / 301` (redirects legacy `/app/` URLs to the root application).
  - `/* /index.html 200` (enables Flutter SPA client-side deep routing for `/login`, `/trips`, etc.).
- `cloudflare/_headers`:
  - Caches CanvasKit and `.wasm` binaries for 1 year (`max-age=31536000, immutable`).
  - Sets `no-cache, no-store, must-revalidate` for `index.html` and `flutter_bootstrap.js` so releases take effect immediately.

---

## 3. Backend API Deployment (Render)

VoyPlan backend is defined as Infrastructure as Code in `render.yaml`.

### Services Configured
- `voyplan-backend`: Node.js Express service (`backend/src/index.js`).
- `voyplan-ai-engineering`: Python FastAPI AI service.

### Deployment Steps
1. Push changes on `main` to GitHub:
   ```bash
   git push origin main
   ```
2. Render automatically triggers a deployment if auto-deploy is enabled on the `voyplan-backend` service.
3. If the service is suspended in Render:
   - Log in to the [Render Dashboard](https://dashboard.render.com).
   - Select `voyplan-backend` (or `travel-v1-mzia`).
   - Click **Resume / Unsuspend Service**.
4. Verify deployment health:
   ```bash
   ./scripts/health-check.sh https://api.voyplan.in
   ```

---

## 4. Mobile Application Build & Distribution

### Android (APK & AAB)
Native Android builds are automated via `.github/workflows/mobile-build.yml`:
1. Push to `main` with changes in `mobile/` builds `mobile/build/app/outputs/flutter-apk/app-release.apk`.
2. The workflow automatically publishes the APK to the rolling GitHub Release tag `android-latest`.
3. To manually build an Android App Bundle (AAB) for Google Play:
   ```bash
   cd mobile
   flutter build appbundle --release --flavor prod \
     --dart-define=APP_ENV=production \
     --dart-define=BACKEND_URL=https://api.voyplan.in \
     --dart-define=MAPBOX_TOKEN="<YOUR_TOKEN>"
   ```

### iOS (Simulator & App Store)
- Simulator build runs on macOS runners in GitHub Actions without codesigning to verify compilation.
- For physical device / TestFlight release:
  ```bash
  cd mobile
  flutter build ipa --release --flavor prod \
    --dart-define=APP_ENV=production \
    --dart-define=BACKEND_URL=https://api.voyplan.in
  ```

---

## 5. Post-Deployment Smoke Verification

Run the end-to-end smoke test suite immediately after deployment:

```bash
./scripts/smoke-test.sh https://voyplan.in https://api.voyplan.in
```
Ensure all 5 stages return `[PASS]`.
