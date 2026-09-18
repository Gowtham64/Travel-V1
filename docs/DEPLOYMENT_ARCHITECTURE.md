# Deployment Architecture

```text
main
  └── GitHub Actions: deploy-production.yml
        ├── Cloudflare Worker: voyplan-api → api.voyplan.in
        └── Cloudflare Pages: voyplan → voyplan.in
              └── Flutter build from mobile/build/web
```

Supabase provides authentication and database storage. The Worker accesses external AI, mapping, routing, and toll providers using Cloudflare Worker secrets.

`backend/` is retained only as migration reference code. It is not a deployment target, fallback service, or part of the production data path.

The production workflow is intentionally ordered: validate credentials, deploy and health-check the Worker, then build and deploy Pages. This makes one branch and one pipeline the source of production truth.
