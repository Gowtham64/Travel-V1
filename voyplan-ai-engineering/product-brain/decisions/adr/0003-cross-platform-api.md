# ADR 0003: Unified Cross-Platform JSON Contract

## Context
VoyPlan serves Web, Android, and iOS from a single Express API. Platform discrepancies in JSON schema cause client deserialization crashes.

## Decision
All itinerary and navigation endpoints must return strictly validated schemas matching the cross-platform contract in `product-brain/architecture/api.md`. Coordinate values are always returned as numbers (`lat`, `lng`), distances in kilometers (`distanceKm`), and durations in minutes (`durationMinutes`).

## Consequences
Guarantees compatibility across Flutter Dart, Android Kotlin, and iOS Swift models.
