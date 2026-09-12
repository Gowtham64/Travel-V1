# ADR 0001: Deterministic Spatial Geometry Validation for AI Itineraries

## Context
Generative AI models hallucinated distant metropolitan cities (Bengaluru, Mysuru, Chennai) when planning a trip to Tirumala.

## Decision
Do not rely solely on system prompt instructions. Implement hard algorithmic spatial validation in `geminiValidatorService.js` combining Haversine boundary filtering ($\le 75\text{ km}$), forbidden city cluster rejection, and commercial category validation.

## Consequences
Guarantees 100% spatial accuracy for local destination sightseeing. Verified by regression test suites.
