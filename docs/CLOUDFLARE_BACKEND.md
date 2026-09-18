# Cloudflare Worker API

The production API is `cloudflare-worker/`, a Hono application deployed as Worker `voyplan-api` at `https://api.voyplan.in`.

## Local checks

```bash
cd cloudflare-worker
npm ci
npm run build
npm test
npx wrangler deploy --dry-run
```

Run locally on the Flutter development URL with `npx wrangler dev --port 3000`.

## Configuration

`wrangler.jsonc` holds non-sensitive metadata, origins, and routing. Keep API credentials in Cloudflare Worker secrets; the complete binding list is in [ENVIRONMENT.md](../ENVIRONMENT.md). Do not place service-role, AI, routing, or toll keys in Flutter defines.

## Release and recovery

The Worker is deployed only by `deploy-production.yml`, before the Pages upload. The workflow requires a successful `GET /health` response before publishing the frontend. To recover, use the Worker deployment history in Cloudflare and then revert the source change on `main`.
