const axios = require("axios");

const ORS_GEOCODE_URL = "https://api.openrouteservice.org/geocode/search";

/**
 * Turn a free-text address into coordinates using OpenRouteService.
 *
 * @param {string} query - e.g. "Bengaluru, India"
 * @returns {Promise<{lat:number, lng:number, displayName:string}|null>}
 */
async function geocodeAddress(query) {
  const apiKey = process.env.ORS_API_KEY || "eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6ImVlMmEyYzUxM2EwNjRmOTNiYTA4MmY0NjEzZDZiOTE5IiwiaCI6Im11cm11cjY0In0=";
  
  if (!apiKey) {

    throw new Error("ORS_API_KEY is not configured in environment variables");
  }

  const response = await axios.get(ORS_GEOCODE_URL, {
    params: { api_key: apiKey, text: query, size: 1, "boundary.country": "IN" },
    timeout: 10000,
  });

  const features = response.data.features;
  if (!features || features.length === 0) return null;

  const result = features[0];
  return {
    lat: result.geometry.coordinates[1], // GeoJSON is [lng, lat]
    lng: result.geometry.coordinates[0],
    displayName: result.properties.label || result.properties.name,
  };
}

module.exports = { geocodeAddress };
