const axios = require("axios");
const { getRouteHash, getCachedRoute, cacheRoute } = require("./dbService");

const ORS_BASE_URL = "https://api.openrouteservice.org/v2/directions/driving-car/geojson";

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

  try {
    if (!mapboxKey) throw new Error("MAPBOX_TOKEN not configured");
    console.log("Fetching traffic-aware route from Mapbox Directions...");
    const coordsString = [start, ...waypoints, end].map(p => `${p.lng},${p.lat}`).join(';');
    // 2-/3-wheelers are banned on access-controlled expressways — exclude motorways for them.
    const excludeParam = avoidMotorways ? "&exclude=motorway" : "";
    const url = `https://api.mapbox.com/directions/v5/mapbox/driving-traffic/${coordsString}?geometries=geojson&overview=full${excludeParam}&access_token=${mapboxKey}`;
    
    const response = await axios.get(url, { timeout: 15000 });
    const route = response.data.routes[0];
    
    if (route) {
      const routeData = {
        distanceKm: Math.round((route.distance / 1000) * 10) / 10,
        durationMin: Math.round(route.duration / 60),
        // GeoJSON coordinates are [lng, lat] - convert to {lat, lng} for the rest of the app
        coordinates: route.geometry.coordinates.map(([lng, lat]) => ({ lat, lng })),
      };
      
      // Save to cache asynchronously
      cacheRoute(hash, routeData);
      return routeData;
    }
  } catch (e) {
    console.error("Mapbox Directions API failed, falling back to OpenRouteService:", e.message);
  }

  // Fallback to OpenRouteService (key loaded from env only — no hardcoded secret).
  const apiKey = process.env.ORS_API_KEY;
  if (!apiKey) {
    throw new Error("Both Mapbox Directions and OpenRouteService APIs failed/unconfigured.");
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

module.exports = { getRoute };
