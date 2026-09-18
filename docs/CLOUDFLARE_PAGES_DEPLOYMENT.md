# Cloudflare Pages Deployment

Cloudflare Pages serves the Flutter production build at `https://voyplan.in` from project `voyplan`.

The single production workflow builds `mobile/build/web` with:

```text
APP_ENV=production
BACKEND_URL=https://api.voyplan.in
```

It copies `cloudflare/_headers` and `cloudflare/_redirects` into the build output, confirms the Pages project exists, deploys it with the locked Wrangler dependency from `cloudflare-worker/`, and checks the live root URL.

## Required setup

1. Create the Pages project `voyplan` and attach `voyplan.in`.
2. Set `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` in GitHub Actions.
3. Keep `CLOUDFLARE_PROJECT_NAME=voyplan` as the workflow variable.
4. Confirm the SPA fallback rule `/* /index.html 200` remains in `cloudflare/_redirects`.

The only deployment source is the generated `mobile/build/web` bundle. The tracked `app/`, `web/`, and `public/` copies are historical static artifacts and are not uploaded by the production workflow.
