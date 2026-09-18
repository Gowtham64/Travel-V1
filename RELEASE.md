# VoyPlan Release Process & Quality Gates

## 1. Release Principles

- **No Unverified Releases**: Every release must pass automated linting, unit tests, and environment checks before deployment.
- **Explicit Deployment Confirmation**: Production deployment workflows require manual confirmation (`DEPLOY`) or a cryptographically signed version tag.
- **Zero Downtime**: Database changes and backend code updates must be backward-compatible with preceding client versions.

---

## 2. Release Steps (End-to-End)

### Step 1: Pre-Release Local Verification
Run the complete automated test suites across both backend and mobile:

```bash
# 1. Run backend unit & integration tests
cd backend && npm test && cd ..

# 2. Run mobile unit & regression tests
cd mobile && flutter analyze --no-fatal-infos && flutter test && cd ..

# 3. Validate environment configuration
./scripts/validate-env.sh production
```

### Step 2: Semantic Version Tagging
VoyPlan uses Semantic Versioning (`vMAJOR.MINOR.PATCH`).
When ready for a new release, create and push an annotated git tag:

```bash
git checkout main
git pull origin main
git tag -a v2.4.1 -m "Release v2.4.1: Fix login redirect loop and enhance readiness probe"
git push origin v2.4.1
```

### Step 3: Triggering Production Web Deployment
Production deployment to Cloudflare Pages is gated.
1. Navigate to **GitHub → Actions → Deploy Production (voyplan.in → Cloudflare Pages)**.
2. Click **Run workflow** on branch `main`.
3. In the input prompt `Type DEPLOY to confirm production deployment`, enter `DEPLOY`.
4. Click **Run workflow**.

### Step 4: Backend Service Update (Render)
1. Ensure the `voyplan-backend` service in Render is connected to the `main` branch.
2. Check deployment status in the Render dashboard.
3. Once the build completes and health checks succeed, verify:
   ```bash
   ./scripts/health-check.sh https://api.voyplan.in
   ```

### Step 5: Mobile App Build & Distribution
1. Pushing to `main` triggers `.github/workflows/mobile-build.yml`.
2. This produces:
   - `travel-app-android-apk` (published automatically to GitHub Release `android-latest`).
   - `travel-app-ios-sim` (simulator build artifact for macOS).
3. For Google Play / App Store distribution, download the release artifacts or trigger store track promotions.

### Step 6: Post-Release Smoke Verification
Immediately run the end-to-end smoke test:

```bash
./scripts/smoke-test.sh https://voyplan.in https://api.voyplan.in
```
Ensure all checks pass cleanly.
