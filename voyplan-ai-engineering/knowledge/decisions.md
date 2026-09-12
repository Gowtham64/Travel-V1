# VoyPlan Architectural Decisions (ADR Log)

## ADR 001: Separation of Autonomous AI Engineering Repository
- **Decision**: House the autonomous AI engineering team in `voyplan-ai-engineering/` as a dedicated repository ignored from `Travel-V1` commits.
- **Rationale**: Prevents AI orchestration code from leaking into the Flutter web production deployment bundle on `gh-pages`.

## ADR 002: Deterministic Spatial Validation Over Pure Prompt Engineering
- **Decision**: Implement spatial bounding (`haversineDistanceKm`) and forbidden city filtering in code (`geminiValidatorService.js`) rather than relying solely on LLM instructions.
- **Rationale**: LLMs can hallucinate plausible-sounding stops; deterministic code guarantees that hard geographic constraints are 100% enforced.

## ADR 003: Five Specialized Agents with Structured JSON Communication
- **Decision**: Deploy 5 discrete agents (R&D, Developer, Tester, QA, Release) communicating via validated JSON schemas (`research-report.json`, `development-result.json`, `test-result.json`, `qa-result.json`, `release-result.json`).
- **Rationale**: Decouples responsibilities, prevents self-bias (QA does not trust Developer claims), and provides an auditable trail.

## ADR 004: Mandatory Human Approval Gate Before Production
- **Decision**: Production deployment requires explicit confirmation keyword `DEPLOY`.
- **Rationale**: Protects production stability, user data, and brand reputation.
