const axios = require("axios");

// Block types that represent an actual geographic place we can geocode.
const PLACE_TYPES = new Set(["activity", "checkin", "checkout", "start", "return", "shopping", "freetime"]);

function haversineKm(a, b) {
  const r = 6371.0;
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return r * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}

/**
 * Geocode a free-text place name to { lat, lng }. Uses OpenRouteService (same
 * key as routing). `focus` (a {lat,lng}) biases results toward that area so a
 * same-named place elsewhere isn't returned. Returns null on failure.
 */
async function geocode(name, near, focus) {
  const key = process.env.ORS_API_KEY;
  if (!key || !name) return null;
  try {
    const params = { api_key: key, text: near ? `${name}, ${near}` : name, size: 1 };
    if (focus) {
      params["focus.point.lat"] = focus.lat;
      params["focus.point.lon"] = focus.lng;
    }
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
async function groundItinerary(days, startLocation = "", destination = "") {
  if (!Array.isArray(days) || !process.env.ORS_API_KEY) return days;
  const cache = new Map();
  let geocodes = 0;

  // Anchor everything on the destination so same-named places elsewhere are
  // rejected. Local stops must be within ~250km of this centre to be trusted.
  const destCenter = destination ? await geocode(destination, "") : null;

  async function coordFor(name, { allowFar = false } = {}) {
    if (!name) return null;
    const kkey = name.toLowerCase().trim();
    if (cache.has(kkey)) return cache.get(kkey);
    if (geocodes >= 40) return null; // stay well under ORS free-tier limits
    geocodes += 1;
    let c = await geocode(name, destination || "", destCenter);
    // Reject a match that lands implausibly far from the destination — almost
    // certainly the wrong same-named place. Keep the AI estimate for that leg.
    if (c && destCenter && !allowFar && haversineKm(destCenter, c) > 250) c = null;
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
      // Only road-route drivable legs. A flight/train/bus/ferry leg must keep
      // the AI's air/rail distance & time — driving-routing it (or failing to)
      // would produce absurd values (e.g. a 5000 km "drive" to another country).
      const mode = String(blocks[i].travelMode || "drive").toLowerCase();
      if (mode !== "drive" && mode !== "walk") continue;
      let from = null;
      for (let j = i - 1; j >= 0; j -= 1) {
        if (blocks[j]._coord) { from = blocks[j]._coord; break; }
      }
      // The first leg of the day often starts from the trip's starting location
      // (which can legitimately be far from the destination).
      if (!from) from = await coordFor(startLocation, { allowFar: true });
      let to = null;
      for (let j = i + 1; j < blocks.length; j += 1) {
        if (blocks[j]._coord) { to = blocks[j]._coord; break; }
      }
      if (from && to) {
        const aiKm = Number(blocks[i].distanceKm) || 0;
        const r = await route(from, to);
        // Only trust the routed value when it broadly agrees with the AI's
        // estimate (or the AI had none). This rejects wrong from/to inferences
        // that collapse to ~0 km or explode to a far same-named place.
        const agrees = aiKm < 1 || (r && r.km >= aiKm * 0.35 && r.km <= aiKm * 3);
        if (r && r.km > 0 && agrees) {
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
