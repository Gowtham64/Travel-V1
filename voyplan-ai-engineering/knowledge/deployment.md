# VoyPlan Deployment & Environments Architecture

## 1. Environment Isolation Model
Three isolated environments:
1. **Development**: Local Node server (`localhost:3000`), local client.
2. **Staging (`staging.voyplan.in`)**: Cloudflare Pages for Web + Render staging web service. Built from `develop` branch.
3. **Production (`voyplan.in`)**: GitHub Pages (`gh-pages` branch) + Render production service (`travel-v1-mzia.onrender.com`).

## 2. Release Promotion Flow
```
feature/* ──PR──▶ develop ──auto──▶ staging.voyplan.in ──QA/E2E──▶ PR ──▶ main ──Human 'DEPLOY'──▶ voyplan.in
```

## 3. Human Approval Gate
Production deployment strictly enforces a human confirmation keyword `DEPLOY`. No autonomous agent is granted unrestricted production credentials.

## 4. Rollback Mechanism
- If production smoke tests fail post-deployment, the Release Agent triggers automated rollback to the previous stable release commit/tag.
- gh-pages preserves full deployment history.
