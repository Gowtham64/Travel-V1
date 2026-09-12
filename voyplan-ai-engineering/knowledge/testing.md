# VoyPlan Testing Strategy & Verification Harness

## 1. Multi-Tier Testing Harness

```
┌────────────────────────────────────────────────────────┐
│               PLAYWRIGHT E2E BROWSER SUITE             │
│  UI user-journey, landing CTA, App loading, live plan  │
└───────────────────────────┬────────────────────────────┘
                            │
┌───────────────────────────▼────────────────────────────┐
│                BACKEND JEST TEST SUITES                │
│  destinationIntegrity, destinationBoundaries, fuel,    │
│  geminiValidationLayer, routeCalculationService        │
└───────────────────────────┬────────────────────────────┘
                            │
┌───────────────────────────▼────────────────────────────┐
│               FLUTTER CLIENT UNIT TESTS                │
│  toll_test.dart, trip_provider_test.dart, models       │
└────────────────────────────────────────────────────────┘
```

## 2. Test Commands
- **Backend Fast Regression**:
  ```bash
  cd backend && npx jest src/tests/destinationBoundaries.test.js --forceExit
  ```
- **Backend Full Test Suite**:
  ```bash
  cd backend && npx jest --forceExit
  ```
- **Mobile Client Tests**:
  ```bash
  cd mobile && flutter test
  ```
- **Playwright E2E Tests**:
  ```bash
  cd voyplan-ai-engineering/tests/e2e && npx playwright test
  ```

## 3. Strict Testing Guardrails
- **No Test Removal**: Tests must NEVER be disabled, muted, or skipped to make CI pass.
- **Assertion Integrity**: Assertions must verify actual requirements, not dummy booleans.
- **Open Handle Mitigation**: Always pass `--forceExit` to Jest in automated scripts to prevent hanging on keep-alive HTTP connections.
