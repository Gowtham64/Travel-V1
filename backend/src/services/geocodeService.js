const axios = require("axios");

// Mapbox token from env only (no committed secret). When unset, geocoding falls
// back to Nominatim automatically (see geocodeAddress).
const MAPBOX_TOKEN = process.env.MAPBOX_TOKEN || "";

/**
 * Geocode with Mapbox — reliable from cloud IPs and does not rate-block the
 * way Nominatim does. Returns null if nothing matches.
 */
async function geocodeWithMapbox(query) {
  if (!MAPBOX_TOKEN) throw new Error("MAPBOX_TOKEN not configured");
  const url = `https://api.mapbox.com/geocoding/v5/mapbox.places/${encodeURIComponent(
    query
  )}.json`;
  const response = await axios.get(url, {
    params: {
      access_token: MAPBOX_TOKEN,
      limit: 1,
      // Worldwide (international destinations must resolve too), biased toward
      // India so domestic place names still win when ambiguous.
      proximity: "78.9629,20.5937",
      language: "en",
    },
    timeout: 10000,
  });

  const features = response.data && response.data.features;
  if (!features || features.length === 0) return null;

  const f = features[0];
  const [lng, lat] = f.center;
  return {
    lat: parseFloat(lat),
    lng: parseFloat(lng),
    displayName: f.place_name || query,
  };
}

/**
 * Fallback geocoder using OpenStreetMap Nominatim. Kept as a secondary in
 * case Mapbox is unavailable.
 */
async function geocodeWithNominatim(query) {
  const response = await axios.get(
    "https://nominatim.openstreetmap.org/search",
    {
      // Worldwide search — no country lock — so international destinations resolve.
      params: { q: query, format: "json", limit: 1 },
      headers: {
        // Nominatim requires a descriptive UA identifying the app.
        "User-Agent":
          "TravelV1/1.0 (https://gowtham64.github.io/Travel-V1/; contact: travel-app)",
      },
      timeout: 10000,
    }
  );

  const data = response.data;
  if (!data || data.length === 0) return null;

  const result = data[0];
  return {
    lat: parseFloat(result.lat),
    lng: parseFloat(result.lon),
    displayName: result.display_name,
  };
}

/**
 * Turn a free-text address into coordinates. Tries Mapbox first, then falls
 * back to Nominatim if Mapbox errors out.
 *
 * @param {string} query - e.g. "Bengaluru, India"
 * @returns {Promise<{lat:number, lng:number, displayName:string}|null>}
 */
async function geocodeAddress(query) {
  try {
    return await geocodeWithMapbox(query);
  } catch (err) {
    console.warn(
      "Mapbox geocode failed, falling back to Nominatim:",
      err.response ? err.response.status : err.message
    );
    return await geocodeWithNominatim(query);
  }
}

/**
 * Autocomplete: return up to `limit` place suggestions for a partial query.
 * Used by the mobile/web planner's destination field. The public Mapbox token
 * shipped in the client is URL-restricted (browser-only), so native apps can't
 * call Mapbox directly — they proxy through here, where the server token (or
 * the free Nominatim fallback) does the lookup.
 *
 * @returns {Promise<Array<{name:string, lat:number, lng:number}>>}
 */
async function suggestPlaces(query, limit = 6) {
  const q = (query || "").trim();
  if (q.length < 2) return [];

  // 0) OpenRouteService (Pelias) autocomplete — PRIMARY. Works from cloud IPs
  //    (unlike Nominatim, which blocks Render), worldwide, purpose-built for
  //    typeahead. Focused on India so domestic places rank first.
  const orsKey = process.env.ORS_API_KEY;
  if (orsKey) {
    try {
      const res = await axios.get(
        "https://api.openrouteservice.org/geocode/autocomplete",
        {
          params: {
            api_key: orsKey,
            text: q,
            size: limit,
            "focus.point.lon": 78.9629,
            "focus.point.lat": 20.5937,
          },
          timeout: 8000,
        }
      );
      const feats = (res.data && res.data.features) || [];
      const list = feats
        .filter(
          (f) =>
            f.geometry &&
            Array.isArray(f.geometry.coordinates) &&
            f.geometry.coordinates.length === 2
        )
        .map((f) => ({
          name: (f.properties && (f.properties.label || f.properties.name)) || "",
          lng: parseFloat(f.geometry.coordinates[0]),
          lat: parseFloat(f.geometry.coordinates[1]),
        }))
        .filter((s) => s.name);
      if (list.length > 0) return list;
    } catch (err) {
      console.warn(
        "ORS autocomplete failed, trying Mapbox/Nominatim:",
        err.response ? err.response.status : err.message
      );
    }
  }

  // 1) Mapbox (best fuzzy matching) using the SERVER token. Worldwide, biased
  //    toward India so domestic places rank first. Skipped/failed silently if
  //    the token is missing or restricted — we fall back to Nominatim.
  if (MAPBOX_TOKEN) {
    try {
      const url = `https://api.mapbox.com/geocoding/v5/mapbox.places/${encodeURIComponent(
        q
      )}.json`;
      const response = await axios.get(url, {
        params: {
          access_token: MAPBOX_TOKEN,
          autocomplete: true,
          limit,
          proximity: "78.9629,20.5937",
          language: "en",
        },
        timeout: 8000,
      });
      const feats = (response.data && response.data.features) || [];
      const list = feats
        .filter((f) => Array.isArray(f.center) && f.center.length === 2)
        .map((f) => ({
          name: f.place_name || "",
          lng: parseFloat(f.center[0]),
          lat: parseFloat(f.center[1]),
        }))
        .filter((s) => s.name);
      if (list.length > 0) return list;
    } catch (err) {
      console.warn(
        "Mapbox autocomplete failed, falling back to Nominatim:",
        err.response ? err.response.status : err.message
      );
    }
  }

  // 2) Free OpenStreetMap Nominatim fallback — worldwide, no token, works from
  //    the server. (No country lock so international destinations resolve.)
  try {
    const response = await axios.get(
      "https://nominatim.openstreetmap.org/search",
      {
        params: { q, format: "json", limit, addressdetails: 0 },
        headers: {
          "User-Agent":
            "TravelV1/1.0 (https://gowtham64.github.io/Travel-V1/; contact: travel-app)",
        },
        timeout: 8000,
      }
    );
    const data = response.data || [];
    return data
      .map((r) => ({
        name: r.display_name || "",
        lat: parseFloat(r.lat),
        lng: parseFloat(r.lon),
      }))
      .filter((s) => s.name && !Number.isNaN(s.lat) && !Number.isNaN(s.lng));
  } catch (err) {
    console.error("Nominatim autocomplete failed:", err.message);
    return [];
  }
}

module.exports = { geocodeAddress, suggestPlaces };
