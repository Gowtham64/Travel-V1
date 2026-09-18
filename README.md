<p align="center"><strong>VoyPlan</strong> — plan the trip, not the chaos.</p>

VoyPlan is an AI-powered road-trip planner for web, Android, and iOS. The production application is a Flutter web SPA on Cloudflare Pages backed by a Cloudflare Worker and Supabase.

- Web: https://voyplan.in/
- API health: https://api.voyplan.in/health
- Android: [Download the APK](https://github.com/Gowtham64/Travel-V1/releases/latest/download/app-prod-release.apk)

## Repository layout

```
.
├── mobile/             Flutter client (web, Android, iOS)
├── cloudflare-worker/  Hono API deployed to api.voyplan.in
├── cloudflare/         Pages headers and SPA redirects
├── backend/            Legacy Express reference; not production infrastructure
├── scripts/            Build, health, and smoke-test helpers
└── .github/workflows/  CI, production deployment, and mobile builds
```

## Local development

Run the Worker on the URL used by the development app configuration:

```bash
cd cloudflare-worker
npm ci
npx wrangler dev --port 3000
```

In another terminal, run the Flutter client:

```bash
cd mobile
flutter pub get
flutter run --dart-define=APP_ENV=development --dart-define=MAPBOX_TOKEN=pk.your_token
```

## Production deployment

Push or merge to `main`. `.github/workflows/deploy-production.yml` deploys the Worker, checks `https://api.voyplan.in/health`, builds the Flutter SPA, and deploys it to the `voyplan` Cloudflare Pages project. See [DEPLOYMENT.md](DEPLOYMENT.md) for prerequisites and verification.

## License

[MIT](LICENSE) © 2026 Gowtham
