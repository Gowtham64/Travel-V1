const axios = require("axios");
const { annotateCumulativeDistance } = require("../utils/geo");

// Multiple Overpass API mirrors — try in order if one fails
const OVERPASS_MIRRORS = [
  "https://overpass-api.de/api/interpreter",
  "https://overpass.kumi.systems/api/interpreter",
  "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
];

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
function sampleRoutePoints(routeCoordinates, sampleEveryKm = 30) {
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

  // Limit to max 15 sample points to avoid oversized queries that get 400 rejected
  if (samples.length > 15) {
    const step = Math.ceil(samples.length / 15);
    const limited = [samples[0]];
    for (let i = step; i < samples.length - 1; i += step) {
      limited.push(samples[i]);
    }
    limited.push(samples[samples.length - 1]);
    return limited;
  }
  return samples;
}

/**
 * Execute an Overpass query, trying each mirror in order until one succeeds.
 *
 * @param {string} query  - Overpass QL query string
 * @returns {Promise<object>}  - Parsed JSON response
 */
async function queryOverpass(query) {
  const encoded = `data=${encodeURIComponent(query)}`;
  let lastError = null;

  for (const url of OVERPASS_MIRRORS) {
    try {
      const response = await axios.post(url, encoded, {
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        timeout: 30000,
      });
      return response.data;
    } catch (err) {
      const status = err.response ? err.response.status : "network";
      console.warn(`Overpass mirror ${url} failed (${status}), trying next...`);
      lastError = err;
    }
  }

  throw lastError || new Error("All Overpass mirrors failed");
}

/**
 * Find points of interest along a route corridor.
 *
 * @param {Array<{lat:number,lng:number}>} routeCoordinates
 * @param {"fuel"|"hotel"|"restaurant"|"attraction"|"hills"|"temple"|"lake"|"river"|"viewpoint"} category
 * @param {number} [radiusMeters=5000] - how far off the route to search at each sample point
 * @param {number} [sampleEveryKm=30] - distance between sample points along the route
 * @returns {Promise<Array<{id:number, name:string, lat:number, lng:number}>>}
 */
async function findPlacesAlongRoute(routeCoordinates, category, radiusMeters = 5000, sampleEveryKm = 30) {
  const filter = CATEGORY_FILTERS[category];
  if (!filter) {
    throw new Error(
      `Unknown category "${category}". Use one of: ${Object.keys(CATEGORY_FILTERS).join(", ")}`
    );
  }

  const samples = sampleRoutePoints(routeCoordinates, sampleEveryKm);

  const clauses = samples
    .map((p) => `node${filter}(around:${radiusMeters},${p.lat},${p.lng});`)
    .join("\n  ");

  const query = `[out:json][timeout:25];\n(\n  ${clauses}\n);\nout body;`;

  const data = await queryOverpass(query);
  const elements = data.elements || [];

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
