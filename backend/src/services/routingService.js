const axios = require("axios");
const { getRouteHash, getCachedRoute, cacheRoute } = require("./dbService");

const ORS_BASE_URL = "https://api.openrouteservice.org/v2/directions/driving-car/geojson";

/** Safe point extractor handling {lat, lng}, {latitude, longitude}, and [lng, lat] */
function toPoint(p) {
  if (!p) return null;
  if (Array.isArray(p)) {
    const lng = Number(p[0]);
    const lat = Number(p[1]);
    if (Number.isFinite(lat) && Number.isFinite(lng)) {
      return { lat, lng };
    }
    return null;
  }
  const rawLat = p.lat ?? p.latitude;
  const rawLng = p.lng ?? p.longitude ?? p.lon;
  if (rawLat != null && rawLng != null) {
    const lat = Number(rawLat);
    const lng = Number(rawLng);
    if (Number.isFinite(lat) && Number.isFinite(lng)) {
      return { lat, lng, name: p.name };
    }
  }
  return null;
}

/** Haversine distance between two points in meters */
function haversineMeters(a, b) {
  const pA = toPoint(a);
  const pB = toPoint(b);
  if (!pA || !pB || isNaN(pA.lat) || isNaN(pB.lat)) return 0;
  const R = 6371000; // meters
  const dLat = ((pB.lat - pA.lat) * Math.PI) / 180;
  const dLng = ((pB.lng - pA.lng) * Math.PI) / 180;
  const sinLat = Math.sin(dLat / 2);
  const sinLng = Math.sin(dLng / 2);
  const h =
    sinLat * sinLat +
    Math.cos((pA.lat * Math.PI) / 180) *
      Math.cos((pB.lat * Math.PI) / 180) *
      sinLng * sinLng;
  return R * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}

/** Haversine distance in km */
function haversineKm(a, b) {
  return haversineMeters(a, b) / 1000;
}

/** Linear interpolation between two {lat,lng} points */
function interpolatePoint(a, b, t) {
  const pA = toPoint(a) || { lat: 0, lng: 0 };
  const pB = toPoint(b) || { lat: 0, lng: 0 };
  return { lat: pA.lat + (pB.lat - pA.lat) * t, lng: pA.lng + (pB.lng - pA.lng) * t };
}

/**
 * Prepares and deduplicates route points for API query strings.
 * Filters out invalid coordinates and consecutive duplicate points (< 5m).
 */
function prepareRoutePoints(start, end, waypoints = []) {
  const pStart = toPoint(start);
  const pEnd = toPoint(end);
  if (!pStart || !pEnd) {
    throw new Error("Start and destination coordinates must be valid numbers");
  }

  const cleanWaypoints = (waypoints || []).map(toPoint).filter(Boolean);
  const rawList = [pStart, ...cleanWaypoints, pEnd];

  // Deduplicate consecutive points within 5m, but preserve start & end for around trips
  const deduplicated = [];
  for (let i = 0; i < rawList.length; i++) {
    const pt = rawList[i];
    if (deduplicated.length > 0 && i < rawList.length - 1) {
      const prev = deduplicated[deduplicated.length - 1];
      if (haversineMeters(prev, pt) < 5) {
        continue; // skip duplicate intermediate point
      }
    }
    deduplicated.push(pt);
  }

  return deduplicated;
}

/**
 * Validate that route coordinates start near origin and end near destination.
 */
function validateRouteStartEnd(start, end, coordinates, maxToleranceMeters = 5000) {
  if (!Array.isArray(coordinates) || coordinates.length < 2) {
    return { valid: false, reason: "Route has fewer than 2 coordinates" };
  }
  const startCoord = coordinates[0];
  const endCoord = coordinates[coordinates.length - 1];

  const startDelta = haversineMeters(start, startCoord);
  const endDelta = haversineMeters(end, endCoord);

  // If start and end are identical (Around Trip), verify that route actually returns to start
  const isAroundTrip = haversineMeters(start, end) < 100;
  if (isAroundTrip && endDelta > maxToleranceMeters) {
    return {
      valid: false,
      reason: `Around Trip did not return to origin. End delta: ${Math.round(endDelta)}m > ${maxToleranceMeters}m`,
      startDelta,
      endDelta,
    };
  }

  const valid = startDelta <= maxToleranceMeters && endDelta <= maxToleranceMeters;
  return {
    valid,
    startDelta,
    endDelta,
    reason: valid ? "OK" : `Start delta: ${Math.round(startDelta)}m, End delta: ${Math.round(endDelta)}m exceeds ${maxToleranceMeters}m`,
  };
}

/**
 * Full End-to-End Route Validator:
 * - Route starts near selected origin
 * - Route ends near selected destination
 * - Route passes through selected waypoints in correct sequence
 * - Distance matches the sum of legs
 * - Around-trip completes full loop
 */
function validateRoute(start, end, waypoints = [], routeResult, maxToleranceMeters = 5000) {
  if (!routeResult) {
    return { valid: false, reason: "Route result is null or undefined" };
  }
  const coords = routeResult.coordinates;
  if (!Array.isArray(coords) || coords.length < 2) {
    return { valid: false, reason: "Route has fewer than 2 coordinates" };
  }

  const baseCheck = validateRouteStartEnd(start, end, coords, maxToleranceMeters);
  if (!baseCheck.valid) {
    return baseCheck;
  }

  // Waypoint sequence validation: verify that the polyline visits waypoints in sequence
  if (Array.isArray(waypoints) && waypoints.length > 0) {
    let lastFoundIdx = -1;
    for (let i = 0; i < waypoints.length; i++) {
      const wp = toPoint(waypoints[i]);
      if (!wp) continue;

      let bestIdx = -1;
      let bestDist = Infinity;
      for (let cIdx = 0; cIdx < coords.length; cIdx++) {
        const d = haversineMeters(wp, coords[cIdx]);
        if (d < bestDist) {
          bestDist = d;
          bestIdx = cIdx;
        }
      }

      if (bestIdx < lastFoundIdx) {
        // If the waypoints are distinct (> 300m apart), an earlier coordinate index means an inversion
        const prevWp = i > 0 ? toPoint(waypoints[i - 1]) : null;
        const distBetweenWps = prevWp ? haversineMeters(prevWp, wp) : Infinity;
        if (distBetweenWps > 300) {
          return {
            valid: false,
            reason: `Waypoint sequence inverted: stop #${i + 1} (${wp.name || ""}) appears before stop #${i} on route coordinates`,
          };
        }
      }
      lastFoundIdx = Math.max(lastFoundIdx, bestIdx);
    }
  }

  // Distance matches sum of legs check
  if (Array.isArray(routeResult.legs) && routeResult.legs.length > 0) {
    const sumLegMeters = routeResult.legs.reduce((acc, l) => acc + (Number(l.distanceMeters) || 0), 0);
    if (sumLegMeters > 0) {
      const delta = Math.abs(routeResult.distanceMeters - sumLegMeters);
      const maxAllowedDelta = Math.max(500, routeResult.distanceMeters * 0.03); // 3% or 500m
      if (delta > maxAllowedDelta) {
        console.warn(`[ROUTE VALIDATION] Route distance (${routeResult.distanceMeters}m) differs from sum of legs (${sumLegMeters}m) by ${delta}m. Normalizing to sum of legs.`);
        routeResult.distanceMeters = sumLegMeters;
        routeResult.distanceKm = Math.round((sumLegMeters / 1000) * 10) / 10;
      }
    }
  }

  return { valid: true, reason: "OK" };
}

/**
 * Log structured diagnostic information for route request.
 */
function logRouteRequest(start, end, waypoints = [], options = {}) {
  const pStart = toPoint(start);
  const pEnd = toPoint(end);
  console.log("==================== ROUTE REQUEST ====================");
  console.log(`Origin:      ${pStart ? `${pStart.lat.toFixed(6)}, ${pStart.lng.toFixed(6)}` : "unknown"} (${start?.name || "unnamed"})`);
  console.log(`Destination: ${pEnd ? `${pEnd.lat.toFixed(6)}, ${pEnd.lng.toFixed(6)}` : "unknown"} (${end?.name || "unnamed"})`);
  console.log(`Waypoints:   ${(waypoints || []).length} stop(s)`);
  if (waypoints && waypoints.length > 0) {
    waypoints.forEach((w, i) => {
      const pW = toPoint(w);
      console.log(`  Stop #${i + 1}: ${pW ? `${pW.lat.toFixed(6)}, ${pW.lng.toFixed(6)}` : "unknown"} (${w?.name || "unnamed"})`);
    });
  }
  console.log(`Profile:     driving-car`);
  console.log(`Options:     avoidMotorways=${Boolean(options?.avoidMotorways)}`);
}

/**
 * Log structured diagnostic information for route response.
 */
function logRouteResponse(start, end, result, provider) {
  const firstPt = result?.coordinates && result.coordinates.length > 0 ? toPoint(result.coordinates[0]) : null;
  const lastPt = result?.coordinates && result.coordinates.length > 0 ? toPoint(result.coordinates[result.coordinates.length - 1]) : null;
  const startDelta = firstPt ? haversineMeters(start, firstPt) : -1;
  const endDelta = lastPt ? haversineMeters(end, lastPt) : -1;

  console.log("==================== ROUTE RESPONSE ====================");
  console.log(`Provider:        ${provider}`);
  console.log(`Distance:        ${result.distanceMeters} m (${result.distanceKm} km)`);
  console.log(`Duration:        ${result.durationSeconds} s (${result.durationMin} min)`);
  console.log(`Leg count:       ${(result.legs || []).length}`);
  console.log(`Points count:    ${(result.coordinates || []).length}`);
  if (firstPt) console.log(`Route Start:     ${firstPt.lat.toFixed(6)}, ${firstPt.lng.toFixed(6)} (delta: ${Math.round(startDelta)}m)`);
  if (lastPt)  console.log(`Route End:       ${lastPt.lat.toFixed(6)}, ${lastPt.lng.toFixed(6)} (delta: ${Math.round(endDelta)}m)`);
  console.log("========================================================");
}

/**
 * Single Canonical RouteResult Builder
 */
function buildCanonicalRouteResult({
  origin,
  destination,
  waypoints = [],
  coordinates,
  geometry,
  distanceMeters,
  durationSeconds,
  legs = [],
  steps = [],
  maneuvers = [],
  avoidedMotorways = false,
  provider = "unknown",
}) {
  const validCoords = Array.isArray(coordinates) ? coordinates : [];
  let distMeters = Math.max(0, Math.round(Number(distanceMeters) || 0));
  let durSeconds = Math.max(0, Math.round(Number(durationSeconds) || 0));

  // Fallback: If distanceMeters is 0 but coordinates exist, compute road haversine sum
  if (distMeters === 0 && validCoords.length >= 2) {
    let sum = 0;
    for (let i = 0; i < validCoords.length - 1; i++) {
      sum += haversineMeters(validCoords[i], validCoords[i + 1]);
    }
    distMeters = Math.round(sum);
  }

  // Fallback: If durationSeconds is 0 but distance exists, assume 60 km/h
  if (durSeconds === 0 && distMeters > 0) {
    durSeconds = Math.round((distMeters / 1000 / 60) * 3600);
  }

  const distKm = Math.round((distMeters / 1000) * 10) / 10;
  const durMin = Math.round(durSeconds / 60);

  const geom =
    geometry && geometry.type === "LineString"
      ? geometry
      : {
          type: "LineString",
          coordinates: validCoords.map((c) => [c.lng, c.lat]),
        };

  return {
    origin: toPoint(origin) || (validCoords.length > 0 ? validCoords[0] : null),
    destination: toPoint(destination) || (validCoords.length > 0 ? validCoords[validCoords.length - 1] : null),
    waypoints: Array.isArray(waypoints) ? waypoints.map(toPoint).filter(Boolean) : [],
    coordinates: validCoords,
    geometry: geom,
    distanceMeters: distMeters,
    distanceKm: distKm,
    durationSeconds: durSeconds,
    durationMin: durMin,
    legs: legs || [],
    steps: steps || [],
    maneuvers: maneuvers || [],
    avoidedMotorways: Boolean(avoidedMotorways),
  };
}

/**
 * Get a driving route between two points using authoritative routing engines.
 *
 * Primary: Mapbox Directions (traffic-aware, turn maneuvers, high resolution)
 * Fallback 1: OpenRouteService (ORS)
 * Fallback 2: Project-OSRM
 *
 * @param {{lat:number,lng:number,name?:string}} start
 * @param {{lat:number,lng:number,name?:string}} end
 * @param {Array<{lat:number,lng:number,name?:string}>} [waypoints] - ordered intermediate stops
 * @param {{avoidMotorways?:boolean}} [options]
 * @returns {Promise<RouteResult>}
 */
async function getRoute(start, end, waypoints = [], options = {}) {
  // Support object-style parameter invocation: getRoute({ origin/start, destination/end, waypoints, options })
  if (start && !end && (start.origin || start.start)) {
    const obj = start;
    start = obj.origin || obj.start;
    end = obj.destination || obj.end;
    waypoints = obj.waypoints || [];
    options = obj.options || {};
  }

  const avoidMotorways = options.avoidMotorways === true;
  logRouteRequest(start, end, waypoints, options);

  const hash = getRouteHash(start, end, waypoints, { avoidMotorways });

  // 1. Try to get from cache first
  const cached = await getCachedRoute(hash);
  if (cached) {
    const coordinatesCount = cached.coordinates ? cached.coordinates.length : 0;
    const distance = cached.distanceKm || 0;
    const isSimplified = distance > 2 && coordinatesCount < 45;

    if (!isSimplified && cached.distanceMeters != null && cached.legs != null) {
      console.log("Serving canonical route from cache...");
      logRouteResponse(start, end, cached, `Cache (${cached.provider || "Supabase"})`);
      return cached;
    }
  }

  // 2. Mapbox Directions API (Primary)
  const mapboxKey = process.env.MAPBOX_TOKEN;
  if (mapboxKey) {
    try {
      console.log("Fetching traffic-aware canonical route from Mapbox Directions...");
      const routePts = prepareRoutePoints(start, end, waypoints);
      const coordsString = routePts.map((p) => `${p.lng.toFixed(6)},${p.lat.toFixed(6)}`).join(";");
      const excludeParam = avoidMotorways ? "&exclude=motorway" : "";
      const url = `https://api.mapbox.com/directions/v5/mapbox/driving-traffic/${coordsString}?geometries=geojson&overview=full&steps=true${excludeParam}&access_token=${mapboxKey}`;

      const response = await axios.get(url, { timeout: 15000 });
      const route = response.data?.routes?.[0];

      if (route && route.geometry && Array.isArray(route.geometry.coordinates) && route.geometry.coordinates.length >= 2) {
        const coords = route.geometry.coordinates.map(([lng, lat]) => ({ lat, lng }));

        const rawLegs = route.legs || [];
        const legs = rawLegs.map((leg, legIdx) => ({
          legIndex: legIdx,
          distanceMeters: Math.round(leg.distance || 0),
          durationSeconds: Math.round(leg.duration || 0),
          steps: (leg.steps || []).map((st) => ({
            instruction: st.maneuver?.instruction || st.name || "Proceed",
            distanceMeters: Math.round(st.distance || 0),
            durationSeconds: Math.round(st.duration || 0),
            roadName: st.name || "",
            maneuverType: st.maneuver?.type || "straight",
            modifier: st.maneuver?.modifier || "",
            location: st.maneuver?.location
              ? { lat: st.maneuver.location[1], lng: st.maneuver.location[0] }
              : null,
          })),
        }));

        const allSteps = legs.flatMap((l) => l.steps);
        const maneuvers = allSteps.map((s) => s.instruction);

        const canonical = buildCanonicalRouteResult({
          origin: start,
          destination: end,
          waypoints,
          coordinates: coords,
          geometry: route.geometry,
          distanceMeters: route.distance,
          durationSeconds: route.duration,
          legs,
          steps: allSteps,
          maneuvers,
          avoidedMotorways,
          provider: "Mapbox",
        });

        const validation = validateRoute(start, end, waypoints, canonical, 5000);
        if (validation.valid) {
          cacheRoute(hash, canonical);
          logRouteResponse(start, end, canonical, "Mapbox");
          return canonical;
        } else {
          console.warn("[ROUTE VALIDATION] Mapbox route failed validation:", validation.reason);
        }
      }
    } catch (e) {
      console.error("Mapbox Directions API failed, falling back to ORS/OSRM:", e.message);
    }
  }

  // 3. Fallback 1: OpenRouteService if API key available
  const apiKey = process.env.ORS_API_KEY;
  if (apiKey) {
    try {
      console.log("Fetching route from OpenRouteService...");
      const routePts = prepareRoutePoints(start, end, waypoints);
      const coordinates = routePts.map((p) => [Number(p.lng.toFixed(6)), Number(p.lat.toFixed(6))]);
      const body = {
        coordinates,
        instructions: true,
        preference: "recommended",
      };
      if (avoidMotorways) {
        body.options = { avoid_features: ["highways"] };
      }

      const response = await axios.post(ORS_BASE_URL, body, {
        headers: {
          Authorization: apiKey,
          "Content-Type": "application/json",
        },
        timeout: 15000,
      });

      const feature = response.data?.features?.[0];
      if (feature && feature.geometry && Array.isArray(feature.geometry.coordinates)) {
        const summary = feature.properties?.summary || {};
        const coords = feature.geometry.coordinates.map(([lng, lat]) => ({ lat, lng }));

        const segments = feature.properties?.segments || [];
        const legs = segments.map((seg, segIdx) => ({
          legIndex: segIdx,
          distanceMeters: Math.round(seg.distance || 0),
          durationSeconds: Math.round(seg.duration || 0),
          steps: (seg.steps || []).map((st) => ({
            instruction: st.instruction || "Follow road",
            distanceMeters: Math.round(st.distance || 0),
            durationSeconds: Math.round(st.duration || 0),
            roadName: st.name || "",
            maneuverType: String(st.type || "straight"),
            modifier: "",
            location: null,
          })),
        }));

        const allSteps = legs.flatMap((l) => l.steps);
        const maneuvers = allSteps.map((s) => s.instruction);

        const canonical = buildCanonicalRouteResult({
          origin: start,
          destination: end,
          waypoints,
          coordinates: coords,
          geometry: feature.geometry,
          distanceMeters: summary.distance,
          durationSeconds: summary.duration,
          legs,
          steps: allSteps,
          maneuvers,
          avoidedMotorways,
          provider: "OpenRouteService",
        });

        const validation = validateRoute(start, end, waypoints, canonical, 5000);
        if (validation.valid) {
          cacheRoute(hash, canonical);
          logRouteResponse(start, end, canonical, "OpenRouteService");
          return canonical;
        } else {
          console.warn("[ROUTE VALIDATION] ORS route failed validation:", validation.reason);
        }
      }
    } catch (e) {
      console.warn("OpenRouteService failed, falling back to OSRM:", e.message);
    }
  }

  // 4. Fallback 2: Public Project-OSRM Router
  return await getOsrmRoute(start, end, waypoints, hash, avoidMotorways);
}

/**
 * Fetch route via OSRM high-resolution engine with steps and legs.
 */
async function getOsrmRoute(start, end, waypoints = [], hash = null, avoidMotorways = false) {
  try {
    const routePts = prepareRoutePoints(start, end, waypoints);
    const coordsStr = routePts.map((p) => `${p.lng.toFixed(6)},${p.lat.toFixed(6)}`).join(";");
    const url = `https://router.project-osrm.org/route/v1/driving/${coordsStr}?overview=full&geometries=geojson&steps=true`;
    console.log("Fetching real highway route from public OSRM router...");
    const resp = await axios.get(url, { timeout: 15000 });
    const route = resp.data?.routes?.[0];

    if (route && route.geometry && Array.isArray(route.geometry.coordinates)) {
      const coords = route.geometry.coordinates.map(([lng, lat]) => ({ lat, lng }));

      const rawLegs = route.legs || [];
      const legs = rawLegs.map((leg, legIdx) => ({
        legIndex: legIdx,
        distanceMeters: Math.round(leg.distance || 0),
        durationSeconds: Math.round(leg.duration || 0),
        steps: (leg.steps || []).map((st) => ({
          instruction: st.maneuver?.instruction || st.name || "Follow the road",
          distanceMeters: Math.round(st.distance || 0),
          durationSeconds: Math.round(st.duration || 0),
          roadName: st.name || "",
          maneuverType: st.maneuver?.type || "straight",
          modifier: st.maneuver?.modifier || "",
          location: st.maneuver?.location
            ? { lat: st.maneuver.location[1], lng: st.maneuver.location[0] }
            : null,
        })),
      }));

      const allSteps = legs.flatMap((l) => l.steps);
      const maneuvers = allSteps.map((s) => s.instruction);

      const canonical = buildCanonicalRouteResult({
        origin: start,
        destination: end,
        waypoints,
        coordinates: coords,
        geometry: route.geometry,
        distanceMeters: route.distance,
        durationSeconds: route.duration,
        legs,
        steps: allSteps,
        maneuvers,
        avoidedMotorways: Boolean(avoidMotorways),
        provider: "OSRM",
      });

      const validation = validateRoute(start, end, waypoints, canonical, 5000);
      if (!validation.valid) {
        console.warn("[ROUTE VALIDATION] OSRM route validation warning:", validation.reason);
      }

      if (hash) cacheRoute(hash, canonical);
      logRouteResponse(start, end, canonical, "OSRM");
      return canonical;
    }
  } catch (err) {
    console.error("OSRM route fetch failed:", err.message);
  }

  // 5. Absolute Last-resort fallback: interpolate along straight line
  console.warn("All routing providers failed. Falling back to emergency road interpolation.");
  const allPts = prepareRoutePoints(start, end, waypoints);
  const interpolated = [];
  let totalDistMeters = 0;

  for (let i = 0; i < allPts.length - 1; i++) {
    const p0 = allPts[i];
    const p1 = allPts[i + 1];
    const d = haversineMeters(p0, p1);
    totalDistMeters += d;
    const steps = Math.max(10, Math.min(50, Math.round(d / 500)));
    for (let s = (i === 0 ? 0 : 1); s <= steps; s++) {
      interpolated.push(interpolatePoint(p0, p1, s / steps));
    }
  }

  const inflatedMeters = Math.round(totalDistMeters * 1.35); // standard road winding factor
  const estDurationSeconds = Math.round((inflatedMeters / 1000 / 60) * 3600); // ~60 km/h average speed

  const canonical = buildCanonicalRouteResult({
    origin: start,
    destination: end,
    waypoints,
    coordinates: interpolated,
    distanceMeters: inflatedMeters,
    durationSeconds: estDurationSeconds,
    legs: [
      {
        legIndex: 0,
        distanceMeters: inflatedMeters,
        durationSeconds: estDurationSeconds,
        steps: [],
      },
    ],
    steps: [],
    maneuvers: [],
    avoidedMotorways: Boolean(avoidMotorways),
    provider: "Emergency Interpolation",
  });

  logRouteResponse(start, end, canonical, "Emergency Interpolation");
  return canonical;
}

module.exports = {
  getRoute,
  getOsrmRoute,
  buildCanonicalRouteResult,
  validateRouteStartEnd,
  validateRoute,
  prepareRoutePoints,
  haversineMeters,
  haversineKm,
  toPoint,
};
