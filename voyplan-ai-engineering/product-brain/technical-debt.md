# VoyPlan Product Brain — Technical Debt Backlog

1. **Dependency Vulnerability Remediation (`npm audit`)**:
   - `baseline-browser-mapping`, `body-parser`, `qs` moderate/high vulnerabilities detected by autonomous scanner.
   - Priority: `P4`.
2. **Offline OSRM Response Caching**:
   - Repeated corridor calculations should hit in-memory Redis or SQLite cache.
   - Priority: `P4`.
3. **Android Auto Head-Unit Mocking**:
   - Simulator tests for `CarMapRenderer.kt` on desktop development workstations.
   - Priority: `P5`.
