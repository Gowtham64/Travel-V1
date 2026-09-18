# VoyPlan Rollback Procedures

## First response

1. Identify the failing layer: Pages, Worker, Supabase, or an external provider.
2. Preserve relevant Worker logs and the failed workflow URL.
3. Roll back the smallest affected layer, then run the smoke checks below.

## Worker rollback

In Cloudflare, open **Workers & Pages → voyplan-api → Deployments** and roll back to the most recent healthy Worker version. Then verify:

```bash
./scripts/health-check.sh https://api.voyplan.in
```

If the bad Worker change is in `main`, revert the commit and let the production workflow make the source-controlled correction permanent.

## Pages rollback

In Cloudflare, open **Workers & Pages → voyplan → Deployments**, select the last healthy deployment, and use its rollback action. Purge only affected HTML/bootstrap URLs if a browser still serves stale content:

- `https://voyplan.in/`
- `https://voyplan.in/index.html`
- `https://voyplan.in/flutter_bootstrap.js`

## Data rollback

Do not roll back database schema or data blindly. Use Supabase backups and a reviewed migration rollback, preserving user-written data. RLS changes should be verified with a non-admin account before restoring traffic.

## Validate recovery

```bash
./scripts/smoke-test.sh https://voyplan.in https://api.voyplan.in
```
