<p align="center"><strong>Voyplan</strong> — plan the trip, not the chaos.</p>

An AI-powered travel planner: one-way road trips and AI round trips with
time-blocked itineraries, live routing, fuel/toll/flight/hotel budgets, vehicle
selection, AI flight/train/hotel suggestions, an active "today" trip view, and a
travel photo gallery. Runs on the web, Android, and iPhone.

- **Web app:** https://gowtham64.github.io/Travel-V1/app/
- **Landing page:** https://gowtham64.github.io/Travel-V1/
- **Android:** [Download the APK](https://github.com/Gowtham64/Travel-V1/releases/latest/download/app-release.apk)
- **iPhone:** [install guide](https://gowtham64.github.io/Travel-V1/ios-install.html)

## Repository layout

```
.
├── backend/       Node.js + Express API (AI planning, routing, budget, prices, account, collab)
├── mobile/        Flutter app (web + Android + iOS) — the client
├── web/           Landing site + install pages, PWA manifest, SideStore source, demo pages
├── docs/          Branding and design notes
├── deploy_web.sh  Builds the Flutter web app + publishes the site to the gh-pages branch
└── LICENSE        MIT
```

## Develop

**Backend**
```bash
cd backend
npm install
cp .env.example .env   # add GEMINI_API_KEY, ORS_API_KEY, Supabase keys, etc.
npm run dev
```

**Mobile (Flutter)**
```bash
cd mobile
flutter pub get
flutter run --dart-define=MAPBOX_TOKEN=pk.your_token
```

## Deploy

- **Web + landing site** → GitHub Pages:
  ```bash
  export MAPBOX_TOKEN=pk.your_url_restricted_token
  ./deploy_web.sh
  ```
  Builds `mobile/` for web into `/app`, copies `web/` to the site root, and
  force-pushes the `gh-pages` branch.
- **Backend** → Render, auto-deploys on push to `main`.
- **Android APK** → built with `flutter build apk --release` and published as
  `Voyplan.apk` at the website root.

## License

[MIT](LICENSE) © 2026 Gowtham
