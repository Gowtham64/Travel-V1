const axios = require("axios");

// Block types that represent an actual geographic place we can geocode.
const PLACE_TYPES = new Set(["activity", "checkin", "checkout", "start", "return", "shopping", "freetime"]);

/**
 * Geocode a free-text place name to { lat, lng }, biased toward `near` when given.
 * Uses OpenRouteService (same key as routing). Returns null on failure.
 */
async function geocode(name, near) {
  const key = process.env.ORS_API_KEY;
  if (!key || !name) return null;
  try {
    const params = { api_key: key, text: near ? `${name}, ${near}` : name, size: 1 };
    const res = await axios.get("https://api.openrouteservice.org/geocode/search", {
      params,
      timeout: 8000,
    });
    const f = res.data && res.data.features && res.data.features[0];
    if (!f || !f.geometry || !Array.isArray(f.geometry.coordinates)) return null;
    const [lng, lat] = f.geometry.coordinates;
    return { lat, lng };
  } catch (_) {
    return null;
  }
}

/**
 * Real driving distance/time between two points via the public OSRM server.
 * Returns { km, min } or null.
 */
async function route(from, to) {
  try {
    const url = `https://router.project-osrm.org/route/v1/driving/${from.lng},${from.lat};${to.lng},${to.lat}`;
    const res = await axios.get(url, { params: { overview: "false" }, timeout: 8000 });
    const r = res.data && res.data.routes && res.data.routes[0];
    if (!r) return null;
    return { km: Math.round((r.distance / 1000) * 10) / 10, min: Math.round(r.duration / 60) };
  } catch (_) {
    return null;
  }
}

/**
 * Replace the AI's guessed travelMin/distanceKm on `travel` blocks with real
 * geocoded + routed values. Best-effort: any block/leg that can't be resolved
 * keeps the AI's original numbers. Mutates `days` in place.
 */
async function groundItinerary(days, startLocation = "") {
  if (!Array.isArray(days) || !process.env.ORS_API_KEY) return days;
  const near = startLocation || (days[0] && days[0].title) || "";
  const cache = new Map();
  let geocodes = 0;

  async function coordFor(name) {
    if (!name) return null;
    const kkey = name.toLowerCase().trim();
    if (cache.has(kkey)) return cache.get(kkey);
    if (geocodes >= 40) return null; // stay well under ORS free-tier limits
    geocodes += 1;
    const c = await geocode(name, near);
    cache.set(kkey, c);
    return c;
  }

  for (const day of days) {
    const blocks = Array.isArray(day.blocks) ? day.blocks : [];

    // Resolve coordinates for the place-like blocks.
    for (const b of blocks) {
      if (PLACE_TYPES.has(b.type)) {
        b._coord = await coordFor(b.place || b.title);
      }
    }

    // For each travel block, route between the nearest located place before and after it.
    for (let i = 0; i < blocks.length; i += 1) {
      if (blocks[i].type !== "travel") continue;
      let from = null;
      for (let j = i - 1; j >= 0; j -= 1) {
        if (blocks[j]._coord) { from = blocks[j]._coord; break; }
      }
      // The first leg of the day often starts from the trip's starting location.
      if (!from) from = await coordFor(startLocation);
      let to = null;
      for (let j = i + 1; j < blocks.length; j += 1) {
        if (blocks[j]._coord) { to = blocks[j]._coord; break; }
      }
      if (from && to) {
        const r = await route(from, to);
        if (r) {
          blocks[i].distanceKm = r.km;
          blocks[i].travelMin = r.min;
          blocks[i].grounded = true;
        }
      }
    }

    // Strip the internal coord field before sending to the client.
    for (const b of blocks) delete b._coord;
  }
  return days;
}

module.exports = { groundItinerary, geocode, route };
