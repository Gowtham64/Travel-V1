# VoyPlan Production Troubleshooting

## Fast triage

```bash
./scripts/health-check.sh https://api.voyplan.in
./scripts/smoke-test.sh https://voyplan.in https://api.voyplan.in
```

## Worker returns 5xx or fails health checks

1. Open the failed production workflow and determine whether the deploy or the post-deploy health gate failed.
2. Inspect **Cloudflare → Workers & Pages → voyplan-api → Logs**, or run `npx wrangler tail voyplan-api` with authorized Cloudflare credentials.
3. Verify the route `api.voyplan.in/*`, `ALLOWED_ORIGINS`, Supabase bindings, and provider secrets.
4. Roll back to the last healthy Worker version if service recovery is urgent.

## Direct navigation returns 404

The Pages bundle must contain `cloudflare/_redirects`, including:

```text
/* /index.html 200
```

The production workflow copies this file into `mobile/build/web/`. Redeploy Pages after correcting a missing or invalid redirect rule.

## Pages deployment fails

- Check that the GitHub secrets `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` are present.
- Confirm the Pages project is named `voyplan`; the workflow checks this before upload.
- Confirm `voyplan.in` is attached to that project and DNS is active.

## Flutter or Worker CI fails

Run the corresponding commands locally:

```bash
cd cloudflare-worker && npm ci && npm run build && npm test
cd ../mobile && flutter pub get && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test
```
