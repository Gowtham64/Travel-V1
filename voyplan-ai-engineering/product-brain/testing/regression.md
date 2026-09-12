# VoyPlan Regression Test Suites

## 1. Destination Boundary Regressions (`backend/src/tests/destinationBoundaries.test.js`)
- **Test 1**: Destination = Tirumala accepts Tirumala/Tirupati; rejects Bengaluru, Mysuru, Chennai.
- **Test 2**: Destination = Goa accepts Goa locations; rejects Mumbai, Bengaluru, Hyderabad.
- **Test 3**: Destination = Ooty accepts Nilgiri sights; rejects Chennai, Bengaluru, Mysuru.
- **Test 4**: Destination = Tirupati accepts local sights; rejects distant metro centers.

## 2. Destination Integrity Corridor Regressions (`backend/src/tests/destinationIntegrity.test.js`)
- Tests complete end-to-end trip generation for Bangalore-Tirumala, Chennai-Tirumala, Hyderabad-Tirumala, Bangalore-Goa, and one-way itineraries.
