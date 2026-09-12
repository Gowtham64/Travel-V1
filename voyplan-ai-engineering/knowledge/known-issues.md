# VoyPlan Known Issues, Root Cause Traces & Architectural Debts

## 1. Resolved Issues

### Issue #123: Deterministic Destination Integrity & AI Planner Random Locations Audit

#### 1. Symptom & Problem Statement
When a user selects **Destination: Tirumala**, the AI itinerary planner was intermittently including distant, unrelated metropolitan cities:
- Bengaluru
- Mysuru
- Chennai
- Hyderabad

#### 2. End-to-End Architectural Trace
The complete execution flow was traced across the system stack:
```
Frontend UI (Flutter / Web)
     │ [Destination: Tirumala, Categories: Temples, Hills]
     ▼
API Endpoint (`POST /api/ai/smart-itinerary`)
     │ [Express 4.19.2 router `routes/ai.js`]
     ▼
Backend Core Service (`services/itineraryEngine.js`)
     │ [Origin/Destination coordinate grounding via `geocodeService.js`]
     ▼
AI Prompt Generation (`services/aiService.js`)
     │ [LLM prompt requesting day-by-day sightseeing candidates]
     ▼
Location Search & Maps Geocoding (`services/geocodeService.js` / OSRM / Mapbox)
     │ [Candidate search for POIs]
     ▼
Itinerary Assembly & Time Scheduling (`services/itineraryEngine.js`)
     │ [Assembly of travel legs and activity blocks]
     ▼
Frontend Rendering (`mobile/lib/screens/itinerary_screen.dart`)
```

#### 3. Root Cause Analysis
- **Why did this happen?** 
  Relying solely on LLM prompt instructions was non-deterministic. When the model hallucinated or suggested generic regional attractions, or when the geocoding service returned famous POIs in distant metropolitan hubs with similar names, the engine lacked a **deterministic spatial geometry boundary guardrail**.
- The engine lacked:
  1. A coordinate-distance ceiling relative to the target destination anchor.
  2. Forbidden city cluster filtering for target travel corridors.
  3. Rejection of deceptive commercial establishments (e.g., "Temple View Restaurant" treated as a religious site).

#### 4. The Deterministic Solution (Not Just Another Prompt)
In `backend/src/services/geminiValidatorService.js`:
1. **Coordinate-based Haversine Distance Bounding**:
   - Destination activities must be within 75 km of the anchored destination coordinate:
     $$\text{distKm} = \text{haversine}(\text{destLat, destLng}, \text{bLat, bLng}) \le 75\text{ km}$$
2. **Deterministic Forbidden City Clusters**:
   - For Tirumala/Tirupati: explicitly rejects Bengaluru, Mysuru, Chennai, Hyderabad, Coimbatore, Ooty, Madurai unless origin matches.
   - For Goa: explicitly rejects Bengaluru, Mumbai, Hyderabad, Chennai, Delhi, Pune.
   - For Ooty: explicitly rejects Chennai, Bengaluru, Mysuru, Hyderabad, Mumbai, Goa.
3. **Deceptive Place Filter**:
   - Verifies commercial keywords (restaurants, hotels, cafes, malls) do not masquerade as genuine spiritual temples or scenic hills.
4. **Controlled Category Taxonomy**:
   - Enforces 16 canonical categories with strict multi-category balance.

#### 5. Regression Verification Suite
- `src/tests/destinationBoundaries.test.js`: **4/4 passed (0.2s)**
  - Test 1: Tirumala accepts Tirumala/Tirupati, rejects distant cities.
  - Test 2: Goa accepts Goa locations, rejects distant metropolitan hubs.
  - Test 3: Ooty accepts Ooty attractions, rejects Chennai/Bengaluru/Mysuru.
  - Test 4: Tirupati accepts local attractions, rejects distant locations.
- `src/tests/destinationIntegrity.test.js`: **8/8 passed (70.3s)**
  - Test A: Bengaluru -> Tirumala (Round Trip) - strictly locks Tirumala, excludes distant cities.
  - Test B: Chennai -> Tirumala (Round Trip) - locks Tirumala, plans destination sights.
  - Test C: Hyderabad -> Tirumala (Round Trip) - locks Tirumala, plans transit corridor.
  - Test D: Bengaluru -> Goa (Round Trip) - locks Goa.
  - Test E: Bengaluru -> Mysuru (Round Trip) - locks Mysuru.
  - Test F: One-way trip (Bengaluru -> Tirumala) - completes at destination without return.
  - Test G: Missing destination pre-flight validation.
  - Test H: Structured place objects with coordinates.

---

## 2. Active Technical Debts & Constraints

1. **Jest Asynchronous Network Handles**:
   - Live external routing requests (OSRM / Mapbox) keep connection sockets open in Jest.
   - *Requirement*: Always use `--forceExit` when running Jest automated pipelines.
2. **Resource Conflict Locking**:
   - Concurrent agents modifying `itineraryEngine.js` and `geminiValidatorService.js` must acquire locks via `taskqueue/queue_manager.py` to prevent merge collisions.
3. **Continuous Priority Scheduling**:
   - P0 (Outage) > P1 (Critical Bug) > P2 (Important Feature) > P3 (Normal) > P4 (Improvement) > P5 (Tech Debt).
