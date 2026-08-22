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
      country: "in", // keep consistent with the app's India focus
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
      params: { q: query, format: "json", limit: 1, countrycodes: "in" },
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

module.exports = { geocodeAddress };
