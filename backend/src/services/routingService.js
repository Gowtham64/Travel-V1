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

  const apiKey = process.env.ORS_API_KEY;
  if (!apiKey) {
    throw new Error("ORS_API_KEY is not set - get a free key at https://openrouteservice.org/dev/#/signup");
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
  const segment = feature.properties.segments[0];

  const routeData = {
    distanceKm: Math.round((segment.distance / 1000) * 10) / 10,
    durationMin: Math.round(segment.duration / 60),
    // GeoJSON coordinates are [lng, lat] - convert to {lat, lng} for the rest of the app
    coordinates: feature.geometry.coordinates.map(([lng, lat]) => ({ lat, lng })),
  };

  // Save to cache asynchronously
  cacheRoute(hash, routeData);

  return routeData;
}

module.exports = { getRoute };
