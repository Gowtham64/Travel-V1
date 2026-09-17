# VoyPlan deployment architecture

## Target topology

```text
Browser
  ├── https://voyplan.in      ── Cloudflare Pages (Flutter Web + static assets)
  ├── https://www.voyplan.in  ── Cloudflare Pages (same production project)
  └── https://api.voyplan.in  ── custom domain ── Render Node/Express API
                                                    ├── Supabase Auth/DB
                                                    ├── routing/geocoding providers
                                                    └── Gemini (server-side only)
```

The repository's source of truth is `mobile/`. The committed `app/`,
`web/app/`, and `public/app/` folders are historical generated copies and are
not used by the new production workflow. The build output is
`mobile/build/web`, with Flutter's base href set to `/` so the domain root
loads the application. Existing `/app/` links are redirected to `/`.

## Responsibility boundaries

- Cloudflare Pages serves HTML, JavaScript, Flutter/CanvasKit assets, fonts,
  images, icons, PWA assets, legal pages, and install resources.
- Render serves the Node.js API under `/api/*` and `/health` only. The Express
  app does not serve Flutter static files.
- Supabase remains the authentication and database layer. Flutter receives only
  the public Supabase URL and publishable/anon key.
- Gemini, Google, Groq, OpenRouter, ORS, TollGuru, and any future privileged
  credentials remain Render environment variables.
- The separate `voyplan-ai-engineering` Python service remains unchanged and is
  not part of the Pages deployment.

## Current Render hostname

The repository currently references `travel-v1-mzia.onrender.com` as the
existing Node backend service. The Render dashboard must be checked before DNS
is changed; this document does not assert that the hostname is still active.
The production client uses `https://api.voyplan.in` and must not be coupled to
the generated Render hostname.

## Independent release model

- Frontend: build and publish the Pages artifact without deploying Render.
- Backend: deploy the `backend/` Node service independently on Render.
- AI engineering: deploy only through its existing Render/CI process.
- Database: apply Supabase migrations separately, after staging and backup.

This makes a static frontend release independent from a backend release while
keeping API contract changes reviewable.

## Rollback

1. In Cloudflare Pages, redeploy the last known-good production deployment.
2. If the problem came from source, revert the migration/feature commit and
   rerun the production workflow.
3. For an API problem, roll back the Render Node service to its last known-good
   deployment; keep the `api.voyplan.in` alias unchanged.
4. Do not roll back Supabase schema changes by deleting data. Use a reviewed
   down migration or a Supabase backup restore.
