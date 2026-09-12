# VoyPlan Product Brain — Known Issues & Regressions

## 1. Resolved Issues
- **Issue #123: AI Planner Random Locations**:
  - Root Cause: Unbounded spatial geometry in LLM prompt allowed distant cities (Bengaluru/Mysuru) into Tirumala trips.
  - Fix: Deterministic Haversine radius validation ($\le 75\text{ km}$) and forbidden city cluster rejection.
  - Verification: `destinationBoundaries.test.js` (4/4 passed), `destinationIntegrity.test.js` (8/8 passed).

## 2. Active Technical Debts
- **Debt 1: Jest Open Asynchronous Handles**: External OSRM HTTP sockets remain open unless `--forceExit` is passed.
- **Debt 2: Local Route Caching**: High test velocity can trigger OSRM rate limits; local mock fixtures recommended for fast offline test cycles.
