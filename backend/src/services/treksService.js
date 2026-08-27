const axios = require("axios");
const { haversineDistanceKm } = require("../utils/geo");

// Reuse the same Overpass mirrors/failover the places service relies on.
const OVERPASS_MIRRORS = [
  "https://overpass-api.de/api/interpreter",
  "https://overpass.kumi.systems/api/interpreter",
  "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
];

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

// OSM sac_scale → a friendly difficulty label (hiking route grading).
const SAC_SCALE_LABELS = {
  hiking: "Easy",
  mountain_hiking: "Moderate",
  demanding_mountain_hiking: "Hard",
  alpine_hiking: "Very hard",
  demanding_alpine_hiking: "Expert",
  difficult_alpine_hiking: "Expert",
};

function difficultyFromTags(tags) {
  if (tags.sac_scale && SAC_SCALE_LABELS[tags.sac_scale]) return SAC_SCALE_LABELS[tags.sac_scale];
  // Fall back to route difficulty if the mapper set one.
  if (tags.difficulty) {
    const d = tags.difficulty.toLowerCase();
    if (d.includes("easy")) return "Easy";
    if (d.includes("moderate") || d.includes("medium")) return "Moderate";
    if (d.includes("hard") || d.includes("difficult")) return "Hard";
  }
  return null;
}

// Parse a length in km from OSM tags (`distance` is usually km, sometimes "12 km").
function lengthKmFromTags(tags) {
  const raw = tags.distance || tags.length;
  if (!raw) return null;
  const m = String(raw).match(/([\d.]+)/);
  if (!m) return null;
  const val = parseFloat(m[1]);
  if (!Number.isFinite(val) || val <= 0) return null;
  // If it looks like metres (e.g. "8000 m"), convert to km.
  if (/m\b/i.test(String(raw)) && !/km/i.test(String(raw))) return Math.round((val / 1000) * 10) / 10;
  return Math.round(val * 10) / 10;
}

// Flatten an Overpass element's `out geom` output into an ordered [{lat,lng}].
// Ways carry `geometry`; relations carry per-member `geometry` we concatenate.
function extractGeometry(el) {
  const pts = [];
  if (Array.isArray(el.geometry)) {
    for (const g of el.geometry) {
      if (g && Number.isFinite(g.lat) && Number.isFinite(g.lon)) pts.push({ lat: g.lat, lng: g.lon });
    }
  } else if (Array.isArray(el.members)) {
    for (const m of el.members) {
      if (m && Array.isArray(m.geometry)) {
        for (const g of m.geometry) {
          if (g && Number.isFinite(g.lat) && Number.isFinite(g.lon)) pts.push({ lat: g.lat, lng: g.lon });
        }
      }
    }
  }
  return pts;
}

// Total length of a polyline in km.
function pathLengthKm(path) {
  let total = 0;
  for (let i = 1; i < path.length; i += 1) total += haversineDistanceKm(path[i - 1], path[i]);
  return total;
}

// Evenly downsample a polyline to at most `maxPoints`, always keeping the ends,
// so large trek relations don't bloat the response.
function simplifyPath(path, maxPoints) {
  if (path.length <= maxPoints) return path;
  const step = Math.ceil(path.length / maxPoints);
  const out = [];
  for (let i = 0; i < path.length; i += step) out.push(path[i]);
  if (out[out.length - 1] !== path[path.length - 1]) out.push(path[path.length - 1]);
  return out;
}

/**
 * Find named hiking/walking trails and trekking routes near a point, AllTrails-style.
 *
 * Sources named `route=hiking`/`route=foot` relations and named `highway=path`
 * ways from OpenStreetMap within the radius, and returns a ranked, de-duplicated
 * list with a representative start coordinate, length, and difficulty where known.
 *
 * @param {number} lat
 * @param {number} lng
 * @param {number} [radiusMeters=20000]
 * @param {number} [limit=20]
 * @returns {Promise<Array<{id:string,name:string,lat:number,lng:number,
 *   distanceFromSearchKm:number,lengthKm:(number|null),difficulty:(string|null),
 *   type:string,tags:object}>>}
 */
async function findTreksNear(lat, lng, radiusMeters = 20000, limit = 20) {
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
    throw new Error("lat and lng must be finite numbers");
  }
  const r = Math.min(Math.max(Number(radiusMeters) || 20000, 1000), 60000);

  // `out geom` returns the actual line geometry (for ways) and member geometries
  // (for relations) so the client can draw the trail, not just a start pin.
  const query =
    `[out:json][timeout:25];\n(\n` +
    `  relation["route"~"hiking|foot|mountain"]["name"](around:${r},${lat},${lng});\n` +
    `  way["highway"="path"]["name"]["sac_scale"](around:${r},${lat},${lng});\n` +
    `  way["highway"~"path|footway"]["name"]["route"="hiking"](around:${r},${lat},${lng});\n` +
    `);\nout geom tags;`;

  const data = await queryOverpass(query);
  const elements = data.elements || [];

  const seen = new Set();
  const treks = [];
  for (const el of elements) {
    const tags = el.tags || {};
    const name = tags.name;
    if (!name) continue;
    // De-dupe by name (a trail can appear as both a relation and its member ways).
    const nameKey = name.toLowerCase().trim();
    if (seen.has(nameKey)) continue;

    const path = extractGeometry(el);
    // Representative point: geometry start, else bbox centre, else element center.
    let elat = path.length ? path[0].lat : null;
    let elng = path.length ? path[0].lng : null;
    if (elat == null && el.bounds) {
      elat = (el.bounds.minlat + el.bounds.maxlat) / 2;
      elng = (el.bounds.minlon + el.bounds.maxlon) / 2;
    }
    if (elat == null) {
      elat = el.lat ?? (el.center && el.center.lat);
      elng = el.lon ?? (el.center && el.center.lon);
    }
    if (elat == null || elng == null) continue;

    seen.add(nameKey);
    const geomLengthKm = path.length > 1 ? pathLengthKm(path) : null;
    treks.push({
      id: `${el.type}/${el.id}`,
      name,
      lat: elat,
      lng: elng,
      distanceFromSearchKm: Math.round(haversineDistanceKm({ lat, lng }, { lat: elat, lng: elng }) * 10) / 10,
      // Prefer the mapper's distance tag; fall back to the measured geometry length.
      lengthKm: lengthKmFromTags(tags) ?? (geomLengthKm ? Math.round(geomLengthKm * 10) / 10 : null),
      difficulty: difficultyFromTags(tags),
      type: tags.route ? `${tags.route} route` : "trail",
      path: simplifyPath(path, 200),
      tags,
    });
  }

  // Nearest first — the most relevant treks to "near this place".
  treks.sort((a, b) => a.distanceFromSearchKm - b.distanceFromSearchKm);
  return treks.slice(0, Math.max(1, Math.min(Number(limit) || 20, 50)));
}

module.exports = {
  findTreksNear,
  difficultyFromTags,
  lengthKmFromTags,
  extractGeometry,
  pathLengthKm,
  simplifyPath,
};
