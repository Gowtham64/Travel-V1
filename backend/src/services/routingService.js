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
 * @returns {Promise<{distanceKm:number, durationMin:number, coordinates:Array<{lat:number,lng:number}>}>}
 */
async function getRoute(start, end, waypoints = []) {
  const hash = getRouteHash(start, end, waypoints);
  
  // Try to get from cache first
  const cached = await getCachedRoute(hash);
  if (cached) {
    console.log("Serving route from Supabase cache...");
    return cached;
  }

  const mapboxKey = process.env.MAPBOX_API_KEY || "pk.eyJ1IjoiZ293dGhhbWVjNjQiLCJhIjoiY21yZzhnOG82MGh2dTJ6c2FuM3h6ZXdkayJ9.PmiHwk5A4-eSWu7zLYkSXQ";
  
  try {
    console.log("Fetching traffic-aware route from Mapbox Directions...");
    const coordsString = [start, ...waypoints, end].map(p => `${p.lng},${p.lat}`).join(';');
    const url = `https://api.mapbox.com/directions/v5/mapbox/driving-traffic/${coordsString}?geometries=geojson&access_token=${mapboxKey}`;
    
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

  // Fallback to OpenRouteService
  const apiKey = process.env.ORS_API_KEY || "eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6ImVlMmEyYzUxM2EwNjRmOTNiYTA4MmY0NjEzZDZiOTE5IiwiaCI6Im11cm11cjY0In0=";
  if (!apiKey) {
    throw new Error("Both Mapbox Directions and OpenRouteService APIs failed/unconfigured.");
  }

  // ORS expects coordinates as [lng, lat], in travel order
  const coordinates = [start, ...waypoints, end].map((p) => [p.lng, p.lat]);

  console.log("Fetching route from OpenRouteService...");
  const response = await axios.post(
    ORS_BASE_URL,
    { coordinates },
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
