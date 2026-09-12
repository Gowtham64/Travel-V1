# ADR 0002: Hybrid OSRM and Mapbox Routing Strategy

## Context
Commercial routing providers charge high per-request API fees during testing and high-traffic periods.

## Decision
Use public Open Source Routing Machine (OSRM) as the primary base router for highway navigation polylines and leg distance calculations. Use Mapbox Directions dynamically for high-congestion traffic re-routing and detailed turn maneuver cards.

## Consequences
Reduces API costs by over 80% while retaining turn-by-turn fidelity. Requires timeout fallbacks if public OSRM throttles.
