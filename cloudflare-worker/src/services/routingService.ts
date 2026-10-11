import { getRouteHash, getCachedRoute, cacheRoute } from "./supabase";

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
 * - Route passes through selected waypoints
 * - Distance matches the sum of legs
 * - Around-trip completes full loop
 */
function validateRoute(start, end, waypoints = [], routeResult, maxToleranceMeters = 10000) {
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

  // Waypoint validation:
  // When an authoritative routing engine (Mapbox, ORS, OSRM) returns legs for the requested
  // sequence [origin, wp0, wp1, ..., wpN, destination], the engine already navigates each leg
  // in the exact requested order.
  if (Array.isArray(waypoints) && waypoints.length > 0) {
    if (Array.isArray(routeResult.legs) && routeResult.legs.length >= waypoints.length) {
      // Check that all legs have valid non-negative distances
      for (let i = 0; i < routeResult.legs.length; i++) {
        const leg = routeResult.legs[i];
        if (leg && Number(leg.distanceMeters) < 0) {
          return { valid: false, reason: `Leg ${i} has negative distance: ${leg.distanceMeters}` };
        }
      }
    } else {
      // Sequence validation along coordinates when legs are not present
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
function logRouteRequest(start: any, end: any, waypoints: any = [], options: any = {}) {
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

/**
 * Regional provider preference to avoid known blind spots and reduce lag.
 * Mapbox is generally best for cities, ORS for remote road trips.
 */
function getProviderPriority(lat, lng) {
  // India region (approx)
  if (lat >= 6.5 && lat <= 37.5 && lng >= 68.0 && lng <= 97.5) {
    return ['mapbox', 'ors', 'osrm'];
  }
  // Europe region (approx)
  if (lat >= 34 && lat <= 71 && lng >= -25 && lng <= 45) {
    return ['mapbox', 'osrm', 'ors'];
  }
  // Default global
  return ['mapbox', 'ors', 'osrm'];
}



async function fetchMapboxRoute(start, end, waypoints, options) {
  const mapboxKey = process.env.MAPBOX_TOKEN;
  if (!mapboxKey) return null;
  try {
    const routePts = prepareRoutePoints(start, end, waypoints);
    let route = null;
    if (routePts.length <= 25) {
      const coordsString = routePts.map((p) => `${p.lng.toFixed(6)},${p.lat.toFixed(6)}`).join(";");
      const excludeParam = options.avoidMotorways ? "&exclude=motorway" : "";
      const url = `https://api.mapbox.com/directions/v5/mapbox/driving-traffic/${coordsString}?geometries=geojson&overview=full&steps=true${excludeParam}&access_token=${mapboxKey}`;
      const response = await fetch(url, { signal: AbortSignal.timeout(12000) });
      const responseData: any = await response.json();
      route = responseData?.routes?.[0];
    } else {
      const chunkSize = 24;
      const mergedRoute: any = { distance: 0, duration: 0, geometry: { type: "LineString", coordinates: [] }, legs: [] };
      for (let i = 0; i < routePts.length - 1; i += (chunkSize - 1)) {
        const slice = routePts.slice(i, Math.min(i + chunkSize, routePts.length));
        if (slice.length < 2) continue;
        const coordsString = slice.map((p) => `${p.lng.toFixed(6)},${p.lat.toFixed(6)}`).join(";");
        const excludeParam = options.avoidMotorways ? "&exclude=motorway" : "";
        const url = `https://api.mapbox.com/directions/v5/mapbox/driving-traffic/${coordsString}?geometries=geojson&overview=full&steps=true${excludeParam}&access_token=${mapboxKey}`;
        const response = await fetch(url, { signal: AbortSignal.timeout(12000) });
        const responseData: any = await response.json();
        const subRoute = responseData?.routes?.[0];
        if (!subRoute || !subRoute.geometry?.coordinates) throw new Error("Mapbox chunk failed");
        mergedRoute.distance += (subRoute.distance || 0);
        mergedRoute.duration += (subRoute.duration || 0);
        const subCoords = subRoute.geometry.coordinates;
        if (mergedRoute.geometry.coordinates.length === 0) mergedRoute.geometry.coordinates.push(...subCoords);
        else mergedRoute.geometry.coordinates.push(...subCoords.slice(1));
        if (Array.isArray(subRoute.legs)) mergedRoute.legs.push(...subRoute.legs);
      }
      route = mergedRoute;
    }
    if (route && route.geometry && Array.isArray(route.geometry.coordinates) && route.geometry.coordinates.length >= 2) {
      const coords = route.geometry.coordinates.map(([lng, lat]: [number, number]) => ({ lat, lng }));
      const legs = (route.legs || []).map((leg: any, legIdx: number) => ({
        legIndex: legIdx,
        distanceMeters: Math.round(leg.distance || 0),
        durationSeconds: Math.round(leg.duration || 0),
        steps: (leg.steps || []).map((st: any) => ({
          instruction: st.maneuver?.instruction || st.name || "Proceed",
          distanceMeters: Math.round(st.distance || 0),
          durationSeconds: Math.round(st.duration || 0),
          roadName: st.name || "",
          maneuverType: st.maneuver?.type || "straight",
          modifier: st.maneuver?.modifier || "",
          location: st.maneuver?.location ? { lat: st.maneuver.location[1], lng: st.maneuver.location[0] } : null,
        })),
      }));
      return buildCanonicalRouteResult({
        origin: start, destination: end, waypoints, coordinates: coords,
        geometry: route.geometry, distanceMeters: route.distance, durationSeconds: route.duration,
        legs, steps: legs.flatMap((l: any) => l.steps), maneuvers: legs.flatMap((l: any) => l.steps).map((s: any) => s.instruction),
        avoidedMotorways: options.avoidMotorways, provider: "Mapbox",
      });
    }
  } catch (e: any) { console.error("Mapbox failed:", e?.message || e); }
  return null;
}

async function fetchOrsRoute(start: any, end: any, waypoints: any, options: any) {
  const apiKey = process.env.ORS_API_KEY;
  if (!apiKey) return null;
  try {
    const routePts = prepareRoutePoints(start, end, waypoints);
    const coordinates = routePts.map((p) => [Number(p.lng.toFixed(6)), Number(p.lat.toFixed(6))]);
    const body: any = { coordinates, instructions: true, preference: "recommended" };
    if (options.avoidMotorways) body.options = { avoid_features: ["highways"] };
    const response = await fetch("https://api.openrouteservice.org/v2/directions/driving-car/geojson", {
      method: "POST", headers: { Authorization: apiKey, "Content-Type": "application/json" },
      body: JSON.stringify(body), signal: AbortSignal.timeout(12000),
    });
    const responseData: any = await response.json();
    const feature = responseData?.features?.[0];
    if (feature && feature.geometry && Array.isArray(feature.geometry.coordinates)) {
      const summary = feature.properties?.summary || {};
      const coords = feature.geometry.coordinates.map(([lng, lat]: [number, number]) => ({ lat, lng }));
      const legs = (feature.properties?.segments || []).map((seg: any, segIdx: number) => ({
        legIndex: segIdx,
        distanceMeters: Math.round(seg.distance || 0),
        durationSeconds: Math.round(seg.duration || 0),
        steps: (seg.steps || []).map((st: any) => ({
          instruction: st.instruction || "Follow road", distanceMeters: Math.round(st.distance || 0),
          durationSeconds: Math.round(st.duration || 0), roadName: st.name || "",
          maneuverType: String(st.type || "straight"), modifier: "", location: null,
        })),
      }));
      return buildCanonicalRouteResult({
        origin: start, destination: end, waypoints, coordinates: coords,
        geometry: feature.geometry, distanceMeters: summary.distance, durationSeconds: summary.duration,
        legs, steps: legs.flatMap((l: any) => l.steps), maneuvers: legs.flatMap((l: any) => l.steps).map((s: any) => s.instruction),
        avoidedMotorways: options.avoidMotorways, provider: "OpenRouteService",
      });
    }
  } catch (e: any) { console.warn("ORS failed:", e?.message || e); }
  return null;
}

async function fetchOsrmRoute(start: any, end: any, waypoints: any, options: any) {
  try {
    const routePts = prepareRoutePoints(start, end, waypoints);
    const coordsStr = routePts.map((p) => `${p.lng.toFixed(6)},${p.lat.toFixed(6)}`).join(";");
    const url = `https://router.project-osrm.org/route/v1/driving/${coordsStr}?overview=full&geometries=geojson&steps=true`;
    const resp = await fetch(url, { signal: AbortSignal.timeout(12000) });
    const respData: any = await resp.json();
    const route = respData?.routes?.[0];
    if (route && route.geometry && Array.isArray(route.geometry.coordinates)) {
      const coords = route.geometry.coordinates.map(([lng, lat]) => ({ lat, lng }));
      const legs = (route.legs || []).map((leg, legIdx) => ({
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
          location: st.maneuver?.location ? { lat: st.maneuver.location[1], lng: st.maneuver.location[0] } : null,
        })),
      }));
      return buildCanonicalRouteResult({
        origin: start, destination: end, waypoints, coordinates: coords,
        geometry: route.geometry, distanceMeters: route.distance, durationSeconds: route.duration,
        legs, steps: legs.flatMap(l => l.steps), maneuvers: legs.flatMap(l => l.steps).map(s => s.instruction),
        avoidedMotorways: options.avoidMotorways, provider: "OSRM",
      });
    }
  } catch (err: any) { console.error("OSRM failed:", err.message); }

  // Emergency Fallback: interpolate along straight line
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

  return buildCanonicalRouteResult({
    origin: start,
    destination: end,
    waypoints,
    coordinates: interpolated,
    geometry: {
      type: "LineString",
      coordinates: interpolated.map((p) => [p.lng, p.lat]),
    },
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
    avoidedMotorways: options.avoidMotorways,
    provider: "Emergency Interpolation",
  });
}

async function getRoute(start: any, end?: any, waypoints: any = [], options: any = {}) {
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

  const cached = await getCachedRoute(hash);
  if (cached && (!cached.distanceKm || cached.distanceKm > 2 || (cached.coordinates && cached.coordinates.length >= 45))) {
    logRouteResponse(start, end, cached, `Cache (${cached.provider || "Supabase"})`);
    return cached;
  }

  const pStart = toPoint(start);
  const pEnd = toPoint(end);
  const priority = getProviderPriority(pStart.lat, pStart.lng);

  const providers: Record<string, Function> = {
    mapbox: fetchMapboxRoute,
    ors: fetchOrsRoute,
    osrm: fetchOsrmRoute,
  };

  for (const providerKey of priority) {
    const fetchFn = providers[providerKey];
    if (!fetchFn) continue;
    const result = await fetchFn(start, end, waypoints, options);
    if (result) {
      const validation = validateRoute(start, end, waypoints, result);
      if (validation.valid) {
        cacheRoute(hash, result);
        logRouteResponse(start, end, result, result.provider);
        return result;
      }
    }
  }

  // Emergency Fallback
  return await fetchOsrmRoute(start, end, waypoints, options);
}
export {
  getRoute,
  fetchOsrmRoute,
  fetchOsrmRoute as getOsrmRoute,
  buildCanonicalRouteResult,
  validateRouteStartEnd,
  validateRoute,
  prepareRoutePoints,
  haversineMeters,
  haversineKm,
  toPoint,
};
