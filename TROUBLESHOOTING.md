# VoyPlan Production Troubleshooting Runbook

## 1. Quick Diagnostic Triage

When an incident is reported, run the automated diagnostic probes immediately:

```bash
# 1. Run full end-to-end smoke test
./scripts/smoke-test.sh https://voyplan.in https://api.voyplan.in

# 2. Check API health and database readiness
./scripts/health-check.sh https://api.voyplan.in

# 3. Verify environment configuration
./scripts/validate-env.sh production
```

---

## 2. Common Production Incidents & Remediation

### Incident A: Users Report Infinite Page Reload / Redirect Loop
- **Symptom**: Navigating to `https://voyplan.in` or logging in causes the browser to reload continuously.
- **Root Cause**: `APP_URL` in `web/index.html` was set to `https://voyplan.in/` instead of `/app/` or dynamically resolving. When `initAuth()` finds a session, `goToApp()` redirects to the same page.
- **Verification**:
  ```bash
  curl -sL https://voyplan.in | grep -E "APP_URL|goToApp"
  ```
- **Remediation**:
  1. Confirm `web/index.html` has the loop-guard logic:
     ```javascript
     if (window.location.href === target || window.location.pathname === '/app/') return;
     ```
  2. Deploy the updated `web/index.html` or trigger a fresh Cloudflare Pages release.
  3. Purge Cloudflare Edge Cache for `https://voyplan.in/index.html` if cached.

---

### Incident B: Backend Returns HTTP 503 Service Suspended
- **Symptom**: `curl -sI https://api.voyplan.in/health` returns `HTTP/2 503 Service Suspended: This service has been suspended by its owner` with header `x-render-routing: suspend-by-user`.
- **Root Cause**: The web service was suspended in the Render console (either manually by the account owner, payment delinquency, or manual toggle).
- **Remediation**:
  1. Log in to [Render Dashboard](https://dashboard.render.com).
  2. Locate the service `voyplan-backend` (or `travel-v1-mzia`).
  3. Click **Settings → Resume Service** (or **Unsuspend**).
  4. Wait ~45 seconds for container initialization, then execute:
     ```bash
     ./scripts/health-check.sh https://api.voyplan.in
     ```
     Verify that `/health` returns `HTTP 200` with `status: "ok"`.

---

### Incident C: Direct Navigation to Routes (e.g. `/login` or `/trips`) Returns 404
- **Symptom**: Clicking links within the app works, but refreshing on `https://voyplan.in/login` returns HTTP 404 Not Found.
- **Root Cause**: Missing SPA catch-all rewrite rule on the hosting provider.
- **Remediation**:
  1. Ensure `cloudflare/_redirects` contains:
     ```text
     /* /index.html 200
     ```
  2. Confirm `cloudflare/_redirects` is copied to the root of `mobile/build/web/` during the build step.
  3. Redeploy to Cloudflare Pages.

---

### Incident D: DNS Resolution Failure on Local Client
- **Symptom**: Terminal returns `curl: (6) Could not resolve host: voyplan.in`.
- **Root Cause**: Local ISP or router DNS resolver caching failure.
- **Remediation**:
  - Test resolution directly against public DNS:
    ```bash
    nslookup voyplan.in 8.8.8.8
    ```
  - If 8.8.8.8 resolves to Cloudflare IPs (`104.21.40.173`), flush local DNS cache:
    ```bash
    sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
    ```

---

### Incident E: CI Build Fails on Flutter Analyze / Tests
- **Symptom**: GitHub Actions CI workflow `ci.yml` fails at step `Analyze` or `Unit tests`.
- **Remediation**:
  1. Run the tests locally in `mobile/`:
     ```bash
     cd mobile
     flutter analyze --no-fatal-infos
     flutter test
     ```
  2. Inspect any compilation or assertion errors.
  3. Ensure no unused imports or strict syntax violations were introduced.
