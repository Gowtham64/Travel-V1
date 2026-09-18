# VoyPlan Emergency Rollback Procedures

## 1. Overview

In the event that an unexpected critical regression occurs in production, follow the tier-specific rollback procedures below. Always announce the incident and rollback action in the team operations channel before and after execution.

---

## 2. Frontend Rollback (Cloudflare Pages)

Cloudflare Pages maintains immutable deployment snapshots, allowing instantaneous 1-click rollbacks with zero build delay.

### Method A: Cloudflare Dashboard (Fastest, < 30 seconds)
1. Log in to the [Cloudflare Dashboard](https://dash.cloudflare.com).
2. Navigate to **Compute (Workers & Pages) → Pages → voyplan**.
3. Under **Deployments**, locate the last known healthy deployment.
4. Click the three dots menu (`...`) next to that deployment and select **Rollback to this deployment**.
5. Confirm the action. Cloudflare's global edge network instantly switches traffic to that deployment snapshot.

### Method B: Wrangler CLI
If CLI access is preferred:
```bash
# List recent deployments
npx wrangler pages deployment list --project-name=voyplan

# Rollback to specific deployment ID
npx wrangler pages deployment rollback <DEPLOYMENT_ID> --project-name=voyplan
```

### Edge Cache Invalidation
To ensure browser caches do not hold stale HTML:
1. In Cloudflare Dashboard, go to **Caching → Configuration → Purge Cache**.
2. Select **Custom Purge** and purge:
   - `https://voyplan.in/`
   - `https://voyplan.in/index.html`
   - `https://voyplan.in/flutter_bootstrap.js`

---

## 3. Backend Rollback (Render)

Render supports rolling back to any previous successful commit deployment without re-compilation.

1. Log in to [Render Dashboard](https://dashboard.render.com).
2. Select the service `voyplan-backend` (or `travel-v1-mzia`).
3. Click the **Events** or **Deploys** tab.
4. Find the previous stable build.
5. Click **Rollback to this deploy**.
6. Render will spin down the regressed container and redirect traffic to the rolled-back revision.
7. Verify health:
   ```bash
   ./scripts/health-check.sh https://api.voyplan.in
   ```

---

## 4. Database Rollback

Because database rollbacks can risk data loss, adhere to these strict rules:
1. **Never drop columns containing newly written customer data** during an emergency rollback.
2. If a migration added a column or index that caused locks or performance degradation:
   ```sql
   -- Drop problematic index concurrently
   DROP INDEX CONCURRENTLY IF EXISTS <problematic_index_name>;
   ```
3. If an RLS policy is blocking valid user access:
   ```sql
   -- Temporarily restore permissive policy for emergency access while diagnosing
   ALTER POLICY "<policy_name>" ON public.trips USING (auth.uid() = user_id);
   ```

---

## 5. Post-Rollback Verification

Execute the full smoke test to confirm that production has returned to a completely healthy state:

```bash
./scripts/smoke-test.sh https://voyplan.in https://api.voyplan.in
```
Ensure all checks return `[PASS]`.
