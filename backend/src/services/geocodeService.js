const axios = require("axios");

/**
 * Turn a free-text address into coordinates using OpenStreetMap Nominatim.
 *
 * @param {string} query - e.g. "Bengaluru, India"
 * @returns {Promise<{lat:number, lng:number, displayName:string}|null>}
 */
async function geocodeAddress(query) {
  const response = await axios.get("https://nominatim.openstreetmap.org/search", {
    params: {
      q: query,
      format: "json",
      limit: 1,
      countrycodes: "in", // Filter to India to keep it consistent
    },
    headers: {
      "User-Agent": "TravelApp/1.0",
    },
    timeout: 10000,
  });

  const data = response.data;
  if (!data || data.length === 0) return null;

  const result = data[0];
  return {
    lat: parseFloat(result.lat),
    lng: parseFloat(result.lon),
    displayName: result.display_name,
  };
}

module.exports = { geocodeAddress };
