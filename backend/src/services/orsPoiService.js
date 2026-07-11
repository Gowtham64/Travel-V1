const axios = require("axios");

const ORS_POI_URL = "https://api.openrouteservice.org/pois";

// Map our requested categories to ORS POI category IDs
// See: https://github.com/GIScience/openrouteservice-docs#pois-category-list
const ORS_CATEGORIES = {
  fuel: [2601], // amenity=fuel
  hotel: [2750], // tourism=hotel
  restaurant: [5601, 5602, 5603], // restaurant, fast_food, cafe
  attraction: [2700], // tourism (general)
  hills: [200], // natural (general, since peak isn't isolated)
  temple: [3100, 3105], // place_of_worship, hindu
  lake: [200], // natural
  river: [200], // natural
  viewpoint: [2740], // tourism=viewpoint
};

async function findPOIsAlongRoute(routeCoordinates, categories) {
  const apiKey = process.env.ORS_API_KEY || "eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6ImVlMmEyYzUxM2EwNjRmOTNiYTA4MmY0NjEzZDZiOTE5IiwiaCI6Im11cm11cjY0In0=";
  if (!apiKey) throw new Error("ORS_API_KEY is not set");

  // Collect all category IDs requested
  const categoryIds = new Set();
  for (const cat of categories) {
    if (ORS_CATEGORIES[cat]) {
      ORS_CATEGORIES[cat].forEach(id => categoryIds.add(id));
    }
  }

  // To avoid hitting geometry limits, we'll use a bounding box approach or simplified geometry
  // For simplicity, let's use the bbox of the route.
  const lats = routeCoordinates.map(c => c.lat);
  const lngs = routeCoordinates.map(c => c.lng);
  
  const minLat = Math.min(...lats);
  const maxLat = Math.max(...lats);
  const minLng = Math.min(...lngs);
  const maxLng = Math.max(...lngs);

  // We can pass GeoJSON LineString to ORS. 
  // We'll downsample coordinates if there are too many (> 100)
  let sampled = routeCoordinates;
  if (sampled.length > 100) {
    const step = Math.ceil(sampled.length / 100);
    sampled = sampled.filter((_, i) => i % step === 0);
  }
  
  const geojson = {
    type: "LineString",
    coordinates: sampled.map(c => [c.lng, c.lat])
  };

  try {
    const response = await axios.post(
      ORS_POI_URL,
      {
        request: "pois",
        geometry: {
          geojson: geojson,
          buffer: 1000 // 1km buffer around the route
        },
        limit: 100, // Return max 100 POIs so we don't overwhelm the mobile app
        sortby: "distance"
      },
      {
        headers: {
          Authorization: apiKey,
          "Content-Type": "application/json",
        },
        timeout: 15000,
      }
    );

    const features = response.data.features || [];
    
    // Map features back to our categories
    const places = {};
    for (const cat of categories) {
      places[cat] = [];
    }

    // Simple mapping: ORS returns `category_ids`. We match against our lists.
    for (const f of features) {
      const point = f.geometry.coordinates; // [lng, lat]
      const tags = f.properties.osm_tags || {};
      const catObj = f.properties.category_ids || {};
      const catIds = Object.keys(catObj).map(Number);
      
      const place = {
        id: f.properties.osm_id,
        name: tags.name || 'Unnamed Place',
        lat: point[1],
        lng: point[0]
      };

      // Put it in the right bucket
      for (const cat of categories) {
        if (ORS_CATEGORIES[cat] && ORS_CATEGORIES[cat].some(id => catIds.includes(id))) {
          places[cat].push(place);
        }
      }
    }

    return places;
  } catch (err) {
    console.error("ORS POI API Error:", err.response?.data || err.message);
    throw err;
  }
}

module.exports = { findPOIsAlongRoute };
