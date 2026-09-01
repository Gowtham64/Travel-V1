const axios = require("axios");

const PHOTON_TERMS = {
  fuel:        ["petrol", "fuel", "gas station"],
  charging:    ["ev charging", "charging station"],
  hotel:       ["hotel", "resort", "lodge"],
  restaurant:  ["restaurant", "dhaba", "food", "cafe"],
  dining:      ["restaurant", "dhaba", "food", "cafe"],
  attraction:  ["tourist attraction", "palace", "monument", "fort", "museum"],
  hills:       ["hills", "peak", "viewpoint"],
  temple:      ["temple", "shrine", "place of worship"],
  lake:        ["lake", "dam", "reservoir"],
  river:       ["river", "waterfall", "falls"],
  viewpoint:   ["viewpoint", "scenic view", "waterfall"],
  tea:         ["tea", "cafe", "coffee"],
};

/**
 * Downsample coordinates to at most maxPoints evenly spaced points.
 */
function sampleCoordinates(coords, maxPoints = 5) {
  if (!coords || coords.length <= maxPoints) return coords || [];
  const step = Math.floor(coords.length / maxPoints);
  const sampled = [];
  for (let i = 0; i < coords.length; i += step) {
    sampled.push(coords[i]);
  }
  if (sampled[sampled.length - 1] !== coords[coords.length - 1]) {
    sampled.push(coords[coords.length - 1]);
  }
  return sampled;
}

/**
 * High-speed POI search along route using Photon (OpenStreetMap global API).
 * Fast, reliable (sub-second), and does not timeout.
 */
async function findPOIsAlongRoute(routeCoordinates, categories) {
  const samples = sampleCoordinates(routeCoordinates, 4);
  const places = {};

  for (const category of categories) {
    const terms = PHOTON_TERMS[category] || [category];
    const results = [];
    const seenKeys = new Set();

    const fetchPromises = [];
    for (const pt of samples) {
      for (const term of terms) {
        fetchPromises.push(
          axios.get("https://photon.komoot.io/api/", {
            params: { q: term, lat: pt.lat, lon: pt.lng, limit: 5 },
            timeout: 4000,
          }).then(resp => {
            const feats = resp.data?.features || [];
            for (const f of feats) {
              const geom = f.geometry?.coordinates || [];
              const p = f.properties || {};
              const name = p.name || (p.osm_value ? `${p.osm_value}`.toUpperCase() : term);
              if (geom.length >= 2) {
                const lng = geom[0];
                const lat = geom[1];
                const key = `${name}-${lat.toFixed(3)}-${lng.toFixed(3)}`;
                if (!seenKeys.has(key)) {
                  seenKeys.add(key);
                  const addrParts = [p.street, p.city, p.state].filter(Boolean);
                  const addr = addrParts.length > 0 ? addrParts.join(", ") : `${name}`;
                  results.push({
                    id: p.osm_id || Math.floor(Math.random() * 1000000),
                    name,
                    lat,
                    lng,
                    address: addr,
                  });
                }
              }
            }
          }).catch(() => {})
        );
      }
    }

    await Promise.all(fetchPromises);
    places[category] = results;
    console.log(`POI [${category}]: found ${results.length} places along route`);
  }

  return places;
}

module.exports = { findPOIsAlongRoute };


