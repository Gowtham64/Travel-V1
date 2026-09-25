import { annotateCumulativeDistance } from "../utils/geo";

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
  charging: '["amenity"="charging_station"]',
  rest_area: '["highway"="rest_area"]',
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
async function queryOverpass(query: string): Promise<any> {
  const encoded = `data=${encodeURIComponent(query)}`;
  let lastError = null;

  for (const url of OVERPASS_MIRRORS) {
    try {
      const response = await fetch(url, {
        method: "POST",
        // Overpass rejects large anonymous route-corridor requests. This is a
        // generic service identifier only; no user or location data is exposed
        // beyond the query itself.
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          Accept: "application/json",
          "User-Agent": "VoyPlan-route-discovery/1.0",
        },
        body: encoded,
        signal: AbortSignal.timeout(15000),
      });
      if (response.ok) {
        return await response.json();
      }
      lastError = new Error(`Overpass mirror returned HTTP ${response.status}`);
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

  // Query nodes, ways AND relations: many real-world features (fuel stations,
  // hotels, lakes) are mapped as areas/ways, not points. `out center` gives those
  // a representative lat/lon so they aren't silently dropped.
  const clauses = samples
    .map((p) => `nwr${filter}(around:${radiusMeters},${p.lat},${p.lng});`)
    .join("\n  ");

  const query = `[out:json][timeout:25];\n(\n  ${clauses}\n);\nout center;`;

  const data = await queryOverpass(query);
  const elements = data.elements || [];

  // De-duplicate (the same place can be picked up by two overlapping samples)
  const seen = new Set();
  const places = [];
  for (const el of elements) {
    const key = `${el.type}/${el.id}`;
    if (seen.has(key)) continue;
    // Nodes carry lat/lon directly; ways/relations carry a computed `center`.
    const lat = el.lat ?? (el.center && el.center.lat);
    const lng = el.lon ?? (el.center && el.center.lon);
    if (lat == null || lng == null) continue;
    // A route discovery card must always name a real mapped place. Skip
    // unnamed OSM features rather than manufacturing a display name.
    const name = el.tags?.name?.trim();
    if (!name) continue;

    seen.add(key);
    places.push({
      id: `osm_${el.type}_${el.id}`,
      name,
      lat,
      lng,
      category,
    });
  }
  return places;
}

export { findPlacesAlongRoute, sampleRoutePoints };
