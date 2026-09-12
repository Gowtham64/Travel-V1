# VoyPlan Testing Strategy & Verification Pyramids

## 1. Multi-Tier Verification Pyramid
1. **Unit Tests (Backend & Dart)**: Fast algorithmic tests for spatial geometry, pricing, and models.
2. **Integration Tests (API & Database)**: Live route validation across OSRM/Mapbox and Supabase tables.
3. **Deterministic Boundary Regression Tests**: Rigorous tests ensuring destination locks are never violated.
4. **End-to-End Browser Tests (Playwright)**: Full browser simulations covering login, trip creation, itinerary reordering, and map interaction.
5. **Mobile Build & Channel Verification**: Flutter test runs and native Kotlin/Swift channel assertions.

## 2. Mandatory Rules
- **Jest Execution Rule**: Always run Jest with `--forceExit` to avoid hanging open keep-alive HTTP connections on OSRM router calls.
- **Zero-Trust QA**: The QA Agent must independently run tests rather than trusting developer assertions.
