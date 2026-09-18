# VoyPlan Environments and Git Flow

VoyPlan uses a single production branch: `main`. Every pull request targets `main`; merging or pushing to it runs CI and the production deployment workflow.

```text
short-lived branch → pull request to main → CI → merge to main → Worker → Pages
```

`main` should be the GitHub default branch and should be protected with the `CI (PR checks)` workflow as a required check.

## Local development

The Flutter application selects local settings with compile-time defines:

```bash
flutter run \
  --dart-define=APP_ENV=development \
  --dart-define=BACKEND_URL=http://localhost:3000 \
  --dart-define=MAPBOX_TOKEN=pk.your_token
```

Run the Worker locally on the same port:

```bash
cd cloudflare-worker
npm ci
npx wrangler dev --port 3000
```

Production builds use `APP_ENV=production` and `https://api.voyplan.in`. There is no shared staging deployment or staging branch.

## Workflows

| Workflow | Purpose |
|---|---|
| `ci.yml` | Flutter and Worker checks for pull requests and `main`. |
| `cloudflare-worker.yml` | Focused Worker typecheck, tests, and bundle dry-run. |
| `deploy-production.yml` | The only production deploy: Worker health gate followed by Pages deployment. |
| `mobile-build.yml` | Android production APK and unsigned iOS simulator build on `main`. |

## One-time account setup

1. Set `main` as GitHub's default branch.
2. Configure Pages project `voyplan` with the production domain.
3. Attach the `api.voyplan.in/*` route to Worker `voyplan-api`.
4. Set the GitHub and Worker secrets in [ENVIRONMENT.md](ENVIRONMENT.md).
