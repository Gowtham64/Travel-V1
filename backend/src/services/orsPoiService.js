const axios = require("axios");

// Multiple Overpass API mirrors — try in order if one fails
const OVERPASS_MIRRORS = [
  "https://overpass-api.de/api/interpreter",
  "https://overpass.kumi.systems/api/interpreter",
  "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
];

// Maps our app-level category names to one or more OSM tag filters. Sightseeing
// categories use several filters so "popular" stops actually return results
// (OSM tags these places inconsistently).
const CATEGORY_FILTERS = {
  fuel:        ['["amenity"="fuel"]'],
  hotel:       ['["tourism"="hotel"]'],
  restaurant:  ['["amenity"="restaurant"]'],
  attraction:  ['["tourism"="attraction"]', '["tourism"="museum"]', '["tourism"="theme_park"]', '["tourism"="zoo"]', '["historic"]'],
  hills:       ['["natural"="peak"]'],
  temple:      ['["amenity"="place_of_worship"]'],
  lake:        ['["natural"="water"]["water"="lake"]', '["natural"="water"]["water"="reservoir"]', '["water"="lake"]'],
  river:       ['["waterway"="river"]'],
  viewpoint:   ['["tourism"="viewpoint"]', '["natural"="waterfall"]'],
  charging:    ['["amenity"="charging_station"]'],
};

// Sightseeing POIs are sparser and worth a longer detour, so search wider.
const WIDE_RADIUS_CATEGORIES = new Set(['attraction', 'viewpoint', 'hills', 'lake', 'river', 'temple']);

/**
 * Execute an Overpass QL query, trying each mirror in order until one succeeds.
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
      if (response.data && response.data.elements) {
        return response.data;
      }
    } catch (err) {
      const status = err.response ? err.response.status : "network";
      console.warn(`Overpass mirror ${url} failed (${status}), trying next...`);
      lastError = err;
    }
  }

  throw lastError || new Error("All Overpass mirrors failed");
}

/**
 * Downsample coordinates to at most maxPoints evenly spaced points.
 */
function sampleCoordinates(coords, maxPoints = 12) {
  if (coords.length <= maxPoints) return coords;
  const step = Math.ceil(coords.length / maxPoints);
  const sampled = [];
  for (let i = 0; i < coords.length; i += step) {
    sampled.push(coords[i]);
  }
  if (sampled[sampled.length - 1] !== coords[coords.length - 1]) {
    sampled.push(coords[coords.length - 1]);
  }
  return sampled;
}

/**
 * Find POIs along a route for multiple categories using Overpass API.
 * One query per category (avoids gigantic merged queries).
 *
 * @param {Array<{lat:number,lng:number}>} routeCoordinates
 * @param {string[]} categories
 * @param {number} [radiusMeters=3000] - search radius at each sample point
 * @returns {Promise<Object<string, Array>>} - { fuel: [...], hotel: [...], ... }
 */
async function findPOIsAlongRoute(routeCoordinates, categories, radiusMeters = 5000) {
  // Downsample to keep queries small (avoids 400 Too Large errors from Overpass)
  const samples = sampleCoordinates(routeCoordinates, 12);

  const places = {};

  for (const category of categories) {
    const filters = CATEGORY_FILTERS[category];
    if (!filters) {
      console.warn(`Unknown POI category: ${category}`);
      places[category] = [];
      continue;
    }

    const radius = WIDE_RADIUS_CATEGORIES.has(category) ? 15000 : radiusMeters;

    // One node clause per (sample point × tag filter) so multi-tag categories
    // (e.g. attraction = tourism|museum|historic) all get searched.
    const clauses = samples
      .map((p) => filters.map((f) => `node${f}(around:${radius},${p.lat},${p.lng});`).join("\n  "))
      .join("\n  ");

    const query = `[out:json][timeout:25];\n(\n  ${clauses}\n);\nout body;`;

    try {
      const data = await queryOverpass(query);
      const elements = data.elements || [];

      // De-duplicate by OSM node ID
      const seen = new Set();
      const results = [];
      for (const el of elements) {
        if (seen.has(el.id)) continue;
        seen.add(el.id);

        const tags = el.tags || {};
        const addressParts = [];
        if (tags["addr:street"]) addressParts.push(tags["addr:street"]);
        if (tags["addr:city"]) addressParts.push(tags["addr:city"]);
        if (tags["addr:state"]) addressParts.push(tags["addr:state"]);

        results.push({
          id: el.id,
          name: tags.name || `Unnamed ${category}`,
          lat: el.lat,
          lng: el.lon,
          address: addressParts.length > 0
            ? addressParts.join(", ")
            : `${el.lat.toFixed(4)}°N, ${el.lon.toFixed(4)}°E`,
        });
      }

      places[category] = results;
      console.log(`POI [${category}]: found ${results.length} places`);
    } catch (err) {
      console.error(`POI lookup failed for category '${category}':`, err.message);
      places[category] = []; // Return empty instead of crashing
    }
  }

  return places;
}

module.exports = { findPOIsAlongRoute };
