# ADR 0004: In-Memory & Cloud Synchronization for Trip Editing

## Context
Travelers need to drag-and-drop, delete, or add stops to generated itineraries on Web and Mobile.

## Decision
Provide immediate optimistic local UI updates with debounced backend persistence (`PUT /api/trips/:id/stops/reorder`). Recalculate road polylines on stop rearrangement while preserving unchanged waypoint legs.

## Consequences
Smooth, latency-free reordering for the user with reliable Supabase cloud persistence.
