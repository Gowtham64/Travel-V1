# VoyPlan Release Process

## Pre-release checks

```bash
cd cloudflare-worker && npm ci && npm run build && npm test && npx wrangler deploy --dry-run
cd ../mobile && flutter pub get && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test
flutter build web --release --dart-define=APP_ENV=production --dart-define=BACKEND_URL=https://api.voyplan.in
```

## Release

1. Open and approve a pull request to `main`.
2. Merge it to `main`.
3. Monitor **Actions → Deploy Production (Cloudflare Worker + Pages)**. The workflow deploys the Worker first and stops if `/health` is not reachable.
4. Use a manually dispatched workflow only when needed; it requires the `DEPLOY` confirmation.
5. Create and push an annotated `vMAJOR.MINOR.PATCH` tag for a versioned release record if appropriate.

## Verification

```bash
./scripts/health-check.sh https://api.voyplan.in
./scripts/smoke-test.sh https://voyplan.in https://api.voyplan.in
```

Check sign-in, a protected API call, and trip creation in the deployed application. The mobile workflow publishes `app-prod-release.apk` to the rolling `android-latest` release after successful `main` builds.
