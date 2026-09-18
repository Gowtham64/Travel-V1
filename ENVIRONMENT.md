# VoyPlan Environment Variables

Never commit real secrets. Cloudflare Worker secrets are set with `npx wrangler secret put <NAME>` from `cloudflare-worker/`; non-secret defaults live in `wrangler.jsonc`.

## Worker bindings

| Name | Stored as | Purpose |
|---|---|---|
| `APP_VERSION`, `ALLOWED_ORIGINS` | Wrangler variable | Runtime metadata and allowed browser origins. |
| `SUPABASE_URL`, `SUPABASE_ANON_KEY` | Wrangler variable | Public Supabase client configuration. |
| `SUPABASE_SERVICE_ROLE_KEY` | Worker secret | Elevated server-side Supabase access. |
| `GEMINI_API_KEY`, `GOOGLE_API_KEY`, `GROQ_API_KEY`, `OPENROUTER_API_KEY` | Worker secret | AI provider credentials. |
| `MAPBOX_TOKEN`, `ORS_API_KEY`, `TOLLGURU_API_KEY` | Worker secret | Mapping, routing, and toll-provider credentials. |
| `PRICE_ADMIN_TOKEN` | Worker secret | Protects administrative price operations. |

Set a secret without exposing it in shell history:

```bash
cd cloudflare-worker
npx wrangler secret put GEMINI_API_KEY
```

## Flutter compile-time configuration

| Define | Production value | Notes |
|---|---|---|
| `APP_ENV` | `production` | Use `development` for local work. |
| `BACKEND_URL` | `https://api.voyplan.in` | Development defaults to `http://localhost:3000`. |
| `MAPBOX_TOKEN` | URL-restricted public token | Client-visible; restrict it in Mapbox. |
| `SUPABASE_URL`, `SUPABASE_ANON_KEY` | Production Supabase project | Public client configuration. |

## GitHub Actions secrets

| Secret | Used for |
|---|---|
| `CLOUDFLARE_API_TOKEN` | Worker and Pages deployment authorization. |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare account selection. |
| `MAPBOX_TOKEN` | Production Flutter web and mobile builds. |

`CLOUDFLARE_PROJECT_NAME=voyplan` is committed workflow configuration, not a secret.
