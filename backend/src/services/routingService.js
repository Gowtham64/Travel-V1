const axios = require("axios");
const { getRouteHash, getCachedRoute, cacheRoute } = require("./dbService");

const ORS_BASE_URL = "https://api.openrouteservice.org/v2/directions/driving-car/geojson";

/** Haversine distance between two points in km */
function haversineKm(a, b) {
  const R = 6371;
  const dLat = ((b.lat - a.lat) * Math.PI) / 180;
  const dLng = ((b.lng - a.lng) * Math.PI) / 180;
  const sinLat = Math.sin(dLat / 2);
  const sinLng = Math.sin(dLng / 2);
  const h =
    sinLat * sinLat +
    Math.cos((a.lat * Math.PI) / 180) *
      Math.cos((b.lat * Math.PI) / 180) *
      sinLng * sinLng;
  return R * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}

/** Linear interpolation between two {lat,lng} points */
function interpolatePoint(a, b, t) {
  return { lat: a.lat + (b.lat - a.lat) * t, lng: a.lng + (b.lng - a.lng) * t };
}

/**
 * Get a driving route between two points using OpenRouteService.
 *
 * Docs: https://openrouteservice.org/dev/#/api-docs
 * Free tier limits (subject to change, check openrouteservice.org/restrictions):
 *  - ~2,500 requests/day, 40,000/month
 *  - max route distance 6,000km, max 50 waypoints
 *
 * @param {{lat:number,lng:number}} start
 * @param {{lat:number,lng:number}} end
 * @param {Array<{lat:number,lng:number}>} [waypoints] - optional intermediate stops
 * @param {{avoidMotorways?:boolean}} [options] - routing constraints. `avoidMotorways`
 *   keeps 2-/3-wheelers off access-controlled expressways that legally ban them.
 * @returns {Promise<{distanceKm:number, durationMin:number, coordinates:Array<{lat:number,lng:number}>}>}
 */
async function getRoute(start, end, waypoints = [], options = {}) {
  const avoidMotorways = options.avoidMotorways === true;
  const hash = getRouteHash(start, end, waypoints, { avoidMotorways });
  
  // Try to get from cache first
  const cached = await getCachedRoute(hash);
  if (cached) {
    const coordinatesCount = cached.coordinates ? cached.coordinates.length : 0;
    const distance = cached.distanceKm || 0;
    const isSimplified = distance > 2 && coordinatesCount < 45;

    if (!isSimplified) {
      console.log("Serving route from Supabase cache...");
      return cached;
    }
    console.log("Cached route is simplified (low-resolution). Bypassing cache to fetch high-resolution route...");
  }

  // Standardized on MAPBOX_TOKEN (matches geocodeService and the reverse-geocode
  // route). No hardcoded fallback — a missing token simply skips Mapbox and
  // falls through to OpenRouteService below.
  const mapboxKey = process.env.MAPBOX_TOKEN;

  if (mapboxKey) {
    try {
      console.log("Fetching traffic-aware route from Mapbox Directions...");
      const coordsString = [start, ...waypoints, end].map(p => `${p.lng},${p.lat}`).join(';');
      const excludeParam = avoidMotorways ? "&exclude=motorway" : "";
      const url = `https://api.mapbox.com/directions/v5/mapbox/driving-traffic/${coordsString}?geometries=geojson&overview=full${excludeParam}&access_token=${mapboxKey}`;
      
      const response = await axios.get(url, { timeout: 15000 });
      const route = response.data.routes[0];
      
      if (route && route.geometry && Array.isArray(route.geometry.coordinates) && route.geometry.coordinates.length > 5) {
        const routeData = {
          distanceKm: Math.round((route.distance / 1000) * 10) / 10,
          durationMin: Math.round(route.duration / 60),
          coordinates: route.geometry.coordinates.map(([lng, lat]) => ({ lat, lng })),
        };
        cacheRoute(hash, routeData);
        return routeData;
      }
    } catch (e) {
      console.error("Mapbox Directions API failed, falling back to ORS/OSRM:", e.message);
    }
  }

  // Fallback 1: Try OpenRouteService if API key is provided
  const apiKey = process.env.ORS_API_KEY;
  if (!apiKey) {
    console.log("No ORS_API_KEY provided, falling back directly to OSRM high-resolution router...");
    return await getOsrmRoute(start, end, waypoints, hash);
  }

  // ── Long-route segmentation ──────────────────────────────────────────
  // ORS caps route distance at 6,000 km.  If the crow-flies distance
  // (inflated ×1.4 for road detours) hints the route will exceed that,
  // split it into ≤5,000 km segments, fetch each, then merge.
  const ORS_SAFE_KM = 5000;
  const allPoints = [start, ...waypoints, end];
  let totalCrowKm = 0;
  for (let i = 0; i < allPoints.length - 1; i++) {
    totalCrowKm += haversineKm(allPoints[i], allPoints[i + 1]);
  }
  const estimatedRoadKm = totalCrowKm * 1.4;

  if (estimatedRoadKm > ORS_SAFE_KM) {
    console.log(
      `Route ~${Math.round(estimatedRoadKm)} km (est.) exceeds ORS 6,000 km cap. Splitting into segments...`
    );
    return await getRouteSegmented(start, end, waypoints, avoidMotorways, apiKey, hash);
  }

  // ORS expects coordinates as [lng, lat], in travel order
  const coordinates = [start, ...waypoints, end].map((p) => [p.lng, p.lat]);

  // For 2-/3-wheelers, tell ORS to avoid highways (its term for motorways/expressways).
  const body = { coordinates };
  if (avoidMotorways) {
    body.options = { avoid_features: ["highways"] };
  }

  console.log("Fetching route from OpenRouteService...");
  const response = await axios.post(
    ORS_BASE_URL,
    body,
    {
      headers: {
        Authorization: apiKey,
        "Content-Type": "application/json",
      },
      timeout: 15000,
    }
  );

  const feature = response.data.features[0];
  const summary = feature.properties.summary;

  const routeData = {
    distanceKm: Math.round((summary.distance / 1000) * 10) / 10,
    durationMin: Math.round(summary.duration / 60),
    coordinates: feature.geometry.coordinates.map(([lng, lat]) => ({ lat, lng })),
  };

  // Save to cache asynchronously
  cacheRoute(hash, routeData);

  return routeData;
}

/**
 * Split a long route into segments and stitch results.
 * Each segment is kept under ~5,000 km (crow-flies) to stay within ORS limits.
 */
async function getRouteSegmented(start, end, waypoints, avoidMotorways, apiKey, hash) {
  // Build ordered list of all points
  const allPoints = [start, ...waypoints, end];

  // Group into segments where each segment's crow-flies distance < 5,000 km
  const ORS_SAFE_KM = 5000;
  const segments = []; // each segment is an array of {lat, lng}
  let current = [allPoints[0]];

  for (let i = 1; i < allPoints.length; i++) {
    const segCrow = segmentCrowKm(current);
    const nextLeg = haversineKm(current[current.length - 1], allPoints[i]);
    if ((segCrow + nextLeg) * 1.4 > ORS_SAFE_KM && current.length > 1) {
      // Close this segment and start a new one from the last point
      segments.push(current);
      current = [current[current.length - 1]];
    }
    current.push(allPoints[i]);
  }
  segments.push(current);

  // If segments are still too long (single straight-line leg > limit), split
  // by inserting interpolated midpoints
  const finalSegments = [];
  for (const seg of segments) {
    if (seg.length === 2) {
      const crow = haversineKm(seg[0], seg[1]);
      if (crow * 1.4 > ORS_SAFE_KM) {
        const numSplits = Math.ceil((crow * 1.4) / ORS_SAFE_KM);
        for (let s = 0; s < numSplits; s++) {
          const p0 = s === 0 ? seg[0] : interpolatePoint(seg[0], seg[1], s / numSplits);
          const p1 = s === numSplits - 1 ? seg[1] : interpolatePoint(seg[0], seg[1], (s + 1) / numSplits);
          finalSegments.push([p0, p1]);
        }
        continue;
      }
    }
    finalSegments.push(seg);
  }

  console.log(`  Split into ${finalSegments.length} segment(s) for ORS.`);

  // Fetch each segment
  let mergedCoords = [];
  let totalDistanceKm = 0;
  let totalDurationMin = 0;

  for (let i = 0; i < finalSegments.length; i++) {
    const seg = finalSegments[i];
    const coords = seg.map((p) => [p.lng, p.lat]);
    const body = { coordinates: coords };
    if (avoidMotorways) {
      body.options = { avoid_features: ["highways"] };
    }

    console.log(`  Fetching segment ${i + 1}/${finalSegments.length} from ORS...`);
    const response = await axios.post(ORS_BASE_URL, body, {
      headers: { Authorization: apiKey, "Content-Type": "application/json" },
      timeout: 30000,
    });

    const feature = response.data.features[0];
    const summary = feature.properties.summary;
    totalDistanceKm += summary.distance / 1000;
    totalDurationMin += summary.duration / 60;

    const segCoords = feature.geometry.coordinates.map(([lng, lat]) => ({ lat, lng }));
    // Skip the first point of subsequent segments to avoid duplicates
    if (i > 0 && segCoords.length > 0) segCoords.shift();
    mergedCoords = mergedCoords.concat(segCoords);
  }

  const routeData = {
    distanceKm: Math.round(totalDistanceKm * 10) / 10,
    durationMin: Math.round(totalDurationMin),
    coordinates: mergedCoords,
  };

  // Cache the stitched result
  cacheRoute(hash, routeData);
  return routeData;
}

async function getOsrmRoute(start, end, waypoints = [], hash = null) {
  try {
    const allPts = [start, ...waypoints, end];
    const coordsStr = allPts.map((p) => `${p.lng},${p.lat}`).join(";");
    const url = `https://router.project-osrm.org/route/v1/driving/${coordsStr}?overview=full&geometries=geojson`;
    console.log("Fetching real highway route from public OSRM router...");
    const resp = await axios.get(url, { timeout: 15000 });
    const route = resp.data?.routes?.[0];
    if (route && route.geometry && Array.isArray(route.geometry.coordinates)) {
      const routeData = {
        distanceKm: Math.round((route.distance / 1000) * 10) / 10,
        durationMin: Math.round(route.duration / 60),
        coordinates: route.geometry.coordinates.map(([lng, lat]) => ({ lat, lng })),
      };
      if (hash) cacheRoute(hash, routeData);
      return routeData;
    }
  } catch (err) {
    console.error("OSRM route fetch failed:", err.message);
  }

  // Last-resort fallback: interpolate along straight line
  const allPts = [start, ...waypoints, end];
  const interpolated = [];
  let totalDist = 0;
  for (let i = 0; i < allPts.length - 1; i++) {
    const p0 = allPts[i];
    const p1 = allPts[i + 1];
    const d = haversineKm(p0, p1);
    totalDist += d;
    for (let step = 0; step <= 25; step++) {
      interpolated.push(interpolatePoint(p0, p1, step / 25));
    }
  }
  return {
    distanceKm: Math.round(totalDist * 1.3 * 10) / 10,
    durationMin: Math.round((totalDist * 1.3 / 60) * 60),
    coordinates: interpolated,
  };
}

/** Total crow-flies distance across a list of points (km) */
function segmentCrowKm(points) {
  let total = 0;
  for (let i = 0; i < points.length - 1; i++) {
    total += haversineKm(points[i], points[i + 1]);
  }
  return total;
}

module.exports = { getRoute, getOsrmRoute };

