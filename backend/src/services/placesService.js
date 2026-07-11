const axios = require("axios");
const { annotateCumulativeDistance } = require("../utils/geo");

const OVERPASS_URL = "https://overpass-api.de/api/interpreter";

// Maps our app-level category names to OSM tag filters.
const CATEGORY_FILTERS = {
  fuel: '["amenity"="fuel"]',
  hotel: '["tourism"="hotel"]',
  restaurant: '["amenity"="restaurant"]',
  attraction: '["tourism"="attraction"]',
  hills: '["natural"="peak"]',
  temple: '["amenity"="place_of_worship"]["religion"="hindu"]',
  lake: '["natural"="water"]["water"="lake"]',
  river: '["waterway"="river"]',
  viewpoint: '["tourism"="viewpoint"]',
};

/**
 * Pick evenly spaced sample points along a route so we don't have to query
 * Overpass once per route vertex (routes can have hundreds of points).
 */
function sampleRoutePoints(routeCoordinates, sampleEveryKm = 25) {
  const annotated = annotateCumulativeDistance(routeCoordinates);
  const totalKm = annotated[annotated.length - 1].cumulativeKm;
  const samples = [annotated[0]];

  let nextSampleKm = sampleEveryKm;
  for (const point of annotated) {
    if (point.cumulativeKm >= nextSampleKm) {
      samples.push(point);
      nextSampleKm += sampleEveryKm;
    }
  }
  if (totalKm > 0) samples.push(annotated[annotated.length - 1]);
  return samples;
}

/**
 * Find points of interest along a route corridor.
 *
 * @param {Array<{lat:number,lng:number}>} routeCoordinates
 * @param {"fuel"|"hotel"|"restaurant"|"attraction"} category
 * @param {number} [radiusMeters=5000] - how far off the route to search at each sample point
 * @param {number} [sampleEveryKm=25] - distance between sample points along the route
 * @returns {Promise<Array<{id:number, name:string, lat:number, lng:number, distanceFromStartKm:number}>>}
 */
async function findPlacesAlongRoute(routeCoordinates, category, radiusMeters = 5000, sampleEveryKm = 25) {
  const filter = CATEGORY_FILTERS[category];
  if (!filter) {
    throw new Error(`Unknown category "${category}". Use one of: ${Object.keys(CATEGORY_FILTERS).join(", ")}`);
  }

  const samples = sampleRoutePoints(routeCoordinates, sampleEveryKm);
  const clauses = samples
    .map((p) => `node${filter}(around:${radiusMeters},${p.lat},${p.lng});`)
    .join("\n  ");

  const query = `
[out:json][timeout:25];
(
  ${clauses}
);
out body;
`;

  const response = await axios.post(OVERPASS_URL, query, {
    headers: { "Content-Type": "text/plain" },
    timeout: 30000,
  });

  const elements = response.data.elements || [];

  // De-duplicate (the same place can be picked up by two overlapping samples)
  const seen = new Set();
  const places = [];
  for (const el of elements) {
    if (seen.has(el.id)) continue;
    seen.add(el.id);
    places.push({
      id: el.id,
      name: (el.tags && el.tags.name) || `Unnamed ${category}`,
      lat: el.lat,
      lng: el.lon,
    });
  }
  return places;
}

module.exports = { findPlacesAlongRoute, sampleRoutePoints };
