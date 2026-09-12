# VoyPlan Security Model & Least Privilege Architecture

## 1. Principles
- **Least Privilege Access**: R&D and Developer agents never possess production credentials. Production deployment keys are isolated exclusively to the Release Agent.
- **Automated Secret Redaction**: All agent logs and terminals pass through regex sanitizers stripping API keys (`pk.*`, `sk-*`, `AIza*`, `ghp_*`).
- **Input Validation & SQL Injection Prevention**: Parameterized queries via Supabase PostgREST client; express-validator on all incoming REST request bodies.
- **Location Privacy**: User GPS coordinates are processed transiently in memory for routing and navigation and never leaked in plain text or client-side telemetry dumps.
