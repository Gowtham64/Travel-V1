# VoyPlan Architecture — Maps & Geospatial Services

## 1. Mapping Providers
- **OSRM (Open Source Routing Machine)**: Primary routing provider (`router.project-osrm.org`) for road network polyline generation and step maneuvers.
- **Mapbox GL JS / Mobile SDK**: High-fidelity vector tile rendering, interactive marker clusters, elevation, and terrain styling.
- **Pelias / Mapbox Geocoding**: Address search, reverse geocoding, and POI bounding.

## 2. Road Network Geometry Caching
- Common highway corridors (e.g. Bangalore-Tirupati, Bangalore-Mysore, Bangalore-Ooty) cache polyline geometries to minimize external network latency and prevent public rate limits.
