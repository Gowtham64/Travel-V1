const axios = require("axios");

const ORS_POI_URL = "https://api.openrouteservice.org/pois";

// Map our requested categories to ORS POI category IDs
// See: https://github.com/GIScience/openrouteservice-docs#pois-category-list
const ORS_CATEGORIES = {
  fuel: [596], // transport -> fuel
  hotel: [108], // accomodation -> hotel
  restaurant: [570], // sustenance -> restaurant
  attraction: [622], // tourism -> attraction
  hills: [335], // natural -> peak
  temple: [135], // arts_and_culture -> place_of_worship
  lake: [340], // natural -> water
  river: [340], // natural -> water
  viewpoint: [627], // tourism -> viewpoint
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

  const requestBody = {
    request: "pois",
    geometry: {
      geojson: geojson,
      buffer: 1000 // 1km buffer around the route
    },
    limit: 100, // Return max 100 POIs so we don't overwhelm the mobile app
    sortby: "distance"
  };

  if (categoryIds.size > 0) {
    requestBody.filters = {
      category_ids: Array.from(categoryIds)
    };
  }

  try {
    const response = await axios.post(
      ORS_POI_URL,
      requestBody,
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
      
      // Build address from available OSM tags
      const addressParts = [];
      if (tags['addr:street']) addressParts.push(tags['addr:street']);
      if (tags['addr:housenumber']) addressParts.push(tags['addr:housenumber']);
      if (tags['addr:city']) addressParts.push(tags['addr:city']);
      if (tags['addr:state']) addressParts.push(tags['addr:state']);
      if (tags['addr:postcode']) addressParts.push(tags['addr:postcode']);
      
      const address = addressParts.length > 0 
        ? addressParts.join(', ') 
        : `${point[1].toFixed(4)}°N, ${point[0].toFixed(4)}°E`;

      const place = {
        id: f.properties.osm_id,
        name: tags.name || 'Unnamed Place',
        lat: point[1],
        lng: point[0],
        address: address,
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
