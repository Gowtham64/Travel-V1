const axios = require("axios");

/**
 * Fetch nearby Wikipedia articles for a coordinate pair (lat, lng).
 * Uses Wikipedia's free public MediaWiki API (no key required).
 *
 * @param {number} lat - Latitude
 * @param {number} lng - Longitude
 * @param {number} [radiusMeters=10000] - Search radius in meters (max 10000)
 * @param {number} [limit=5] - Max results to return
 * @returns {Promise<Array<{title: string, summary: string, pageUrl: string, thumbnailUrl: string|null, lat: number, lng: number, distanceMeters: number}>>}
 */
async function getWikiPlaces(lat, lng, radiusMeters = 10000, limit = 5) {
  if (typeof lat !== "number" || typeof lng !== "number") {
    return [];
  }

  try {
    const geoUrl = `https://en.wikipedia.org/w/api.php?action=query&list=geosearch&gscoord=${lat}|${lng}&gsradius=${Math.min(radiusMeters, 10000)}&gslimit=${limit}&format=json&origin=*`;
    const geoRes = await axios.get(geoUrl, { timeout: 8000 });
    const pages = geoRes.data?.query?.geosearch || [];

    if (pages.length === 0) return [];

    const pageIds = pages.map((p) => p.pageid).join("|");
    const detailUrl = `https://en.wikipedia.org/w/api.php?action=query&pageids=${pageIds}&prop=pageimages|extracts&pithumbsize=400&exintro=1&explaintext=1&exchars=200&format=json&origin=*`;
    const detailRes = await axios.get(detailUrl, { timeout: 8000 });
    const detailPages = detailRes.data?.query?.pages || {};

    return pages.map((p) => {
      const info = detailPages[p.pageid] || {};
      return {
        pageid: p.pageid,
        title: p.title,
        lat: p.lat,
        lng: p.lng,
        distanceMeters: Math.round(p.dist),
        summary: info.extract || "No summary available.",
        thumbnailUrl: info.thumbnail?.source || null,
        pageUrl: `https://en.wikipedia.org/?curid=${p.pageid}`,
      };
    });
  } catch (err) {
    console.warn("Wikipedia geosearch failed:", err.message);
    return [];
  }
}

module.exports = {
  getWikiPlaces,
};
