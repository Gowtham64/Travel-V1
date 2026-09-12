# VoyPlan Platform — Web Architecture

## 1. Hosting & Deployment
- Production URL: `https://voyplan.in`
- Staging URL: `https://staging.voyplan.in`
- Architecture: Static HTML5 landing & installer portals at `/` with compiled Flutter Web SPA served under `/app/`.
- Deployment Pipeline: `deploy_web.sh` compiles Flutter web, copies `web/*` and builds into `./public`, writes `CNAME`, and commits to `gh-pages`.

## 2. Browser Compatibility
- Targets: Chromium (Chrome, Edge, Brave), Safari, Firefox.
- Tested via Playwright end-to-end automation.
