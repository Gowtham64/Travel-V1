# VoyPlan 24/7 Autonomous AI Product Engineering Organization

An autonomous, continuously operating AI product engineering company designed around the [VoyPlan](https://voyplan.in) platform (`Gowtham64/Travel-V1`).

This is **NOT** a simple coding assistant or collection of independent AI agents. It is a coordinated AI engineering organization where multiple specialized agents continuously communicate, debate decisions in an AI Product Council, consult a shared Product Brain, implement changes through **Google Antigravity**, validate cross-platform across Web, Android, iOS, deploy safely, and monitor 24/7.

---

## 1. Core Technology & Role Mapping

The VoyPlan AI Engineering Organization is built on the following foundational architecture:

| Role | Technology | Implementation & Reference |
| :--- | :--- | :--- |
| **Product/R&D/QA orchestration** | **OpenHands SDK** | `agents/common/openhands_adapter.py` providing conversation loops, tool calling, and workspace execution. |
| **24/7 scheduling/event dispatch** | **OpenHands Automation / custom orchestrator** | `orchestrator_daemon.py` + `taskqueue/queue_manager.py` handling continuous priority scheduling (P0–P5), automated radar scanning, and webhooks. |
| **Actual coding** | **Google Antigravity** | **Primary implementation worker**. Antigravity performs all source inspection, frontend, backend, APIs, database, AI, maps, and tests. |
| **Web E2E** | **Playwright** | `tests/e2e/voyplan-itinerary.spec.js` + `playwright.config.js` running automated cross-browser flows (Chromium, Firefox, WebKit). |
| **CI/CD** | **GitHub Actions** | `.github/workflows/ai-engineering.yml` orchestrating issue-triggered builds, automated test execution, and deployment pipelines. |
| **Agent isolation** | **Docker** | `docker-compose.yml` isolating the orchestrator daemon, dashboard server, OpenHands sandbox, and test runners. |
| **Optional local models** | **Ollama** | `agents/common/llm_client.py` supporting local open models (`qwen2.5-coder:latest`, `deepseek-coder`, `llama3`) for zero-cost R&D and triage. |
| **Source control** | **GitHub** | `Gowtham64/Travel-V1` & `voyplan-ai-engineering` with branch protection (`feature/*` → `develop` → `staging` → `main`). |
| **Shared memory** | **Product Brain + persistent DB** | 28 architectural and ADR documents in `product-brain/` + persistent queue state in `taskqueue/task_queue.json`. |
| **Production** | **Existing VoyPlan deployment** | `https://voyplan.in`, `deploy_web.sh`, Supabase PostgreSQL, and automated staging/gh-pages release pipelines. |

---

## 2. 8-Agent Coordinated Pipeline

```
VOYPLAN AI COMPANY
        │
  AI ORCHESTRATOR (OpenHands Automation + Custom Daemon)
        │
 ┌──────┴───────────────┬──────────────────────┐
 │                      │                      │
 ▼                      ▼                      ▼
PRODUCT AGENT       R&D AGENT           SECURITY AGENT
(OpenHands SDK)    (OpenHands SDK)      (OpenHands SDK)
 │                      │                      │
 └──────┬───────────────┴──────────────────────┘
        │
  PRODUCT COUNCIL (Structured Debate & Consensus)
        │
        ▼ TECHNICAL DECISION
GOOGLE ANTIGRAVITY DEVELOPER (Primary Code Writer)
 ┌──────┴───────────────┬──────────────────────┐
 ▼                      ▼                      ▼
WEBSITE              ANDROID                  IOS
 │                      │                      │
 └──────┬───────────────┴──────────────────────┘
        ▼
     BACKEND (Node.js/Express)
        │ DATABASE (Supabase)
        │ AI / MAPS (Gemini, Mapbox, OSRM)
        ▼
  TESTING AGENT (Jest Backend Suites + Playwright Web E2E)
        │
        ▼
     QA AGENT (OpenHands SDK Zero-Trust Acceptance & 3-Retry Loop)
        │
        ▼
  SECURITY AGENT (OpenHands SDK Audit: Secrets, CVEs, Location Privacy)
        │
        ▼
  RELEASE AGENT (Staging Deployment, Human Approval Gate 'DEPLOY', Smoke Tests)
        │
        ▼
    PRODUCTION (voyplan.in)
        │
        ▼
    MONITORING ────→ ORCHESTRATOR (24/7 Autonomous Cycle)
```

---

## 3. Quickstart

### 1. Start the Live 24/7 Operations Hub
```bash
python3 dashboard/server.py
```
Open **`http://localhost:3050/`** to view live agent states, the AI Product Council debate stream, priority queues, and operator emergency controls.

### 2. Run Single Issue Pipeline
```bash
python3 orchestrator.py --issue 123 --title "Fix AI Planner Random Locations"
```

### 3. Run 24/7 Continuous Autonomous Daemon
```bash
python3 orchestrator_daemon.py
```

### 4. Isolated Docker Environment
```bash
docker compose up -d
```

---

## 4. Production Safety & Guardrails
- **Antigravity as Primary Developer**: Open-source tools provide supporting infrastructure; all actual VoyPlan code changes are implemented by Google Antigravity.
- **No Direct Push to Production**: Agents never push directly to `main` or `gh-pages`.
- **Human Approval Gate**: Production deployment requires explicit human confirmation (`DEPLOY`).
- **Automated Rollback**: If production smoke tests fail, the Release Agent instantly reverts to the last known good release.
- **Operator Emergency Controls**: Single-click `STOP ALL AGENTS`, `Pause`, `Resume`, and `Rollback` in the operations dashboard.
