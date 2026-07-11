const axios = require("axios");

const NOMINATIM_URL = "https://nominatim.openstreetmap.org/search";

/**
 * Turn a free-text address into coordinates using Nominatim (OpenStreetMap's
 * free geocoder - no API key, but usage-policy limited to ~1 request/second
 * and requires a descriptive User-Agent, which is why this lives server-side
 * rather than being called directly from the mobile app).
 *
 * Usage policy: https://operations.osmfoundation.org/policies/nominatim/
 *
 * @param {string} query - e.g. "Bengaluru, India"
 * @returns {Promise<{lat:number, lng:number, displayName:string}|null>}
 */
async function geocodeAddress(query) {
  const response = await axios.get(NOMINATIM_URL, {
    params: { q: query, format: "json", limit: 1 },
    headers: {
      "User-Agent": "travel-itinerary-app/0.1 (contact: gowthampec64@gmail.com)",
    },
    timeout: 10000,
  });

  const result = response.data[0];
  if (!result) return null;

  return {
    lat: parseFloat(result.lat),
    lng: parseFloat(result.lon),
    displayName: result.display_name,
  };
}

module.exports = { geocodeAddress };
