const axios = require("axios");

const TOLLGURU_URL = "https://apis.tollguru.com/toll/v2/origin-destination-waypoints";

/**
 * Vehicle types TollGuru accepts (US-centric axle classes, also used for India/Canada/Mexico routes).
 * Pick the closest match for your vehicle. Full list: https://tollguru.com/toll-api-docs
 */
const VEHICLE_TYPES = {
  car: "2AxlesAuto",
  suv: "2AxlesAuto",
  motorcycle: "2AxlesMotorcycle",
  bus: "2AxlesBus",
  rv: "2AxlesRv",
  truck2axle: "2AxlesTruck",
  truck3axle: "3AxlesTruck",
};

/**
 * Approximate India toll rates per plaza by vehicle type (INR).
 * Based on NHAI average rates for car class.
 */
const INDIA_TOLL_RATE_PER_PLAZA = {
  car: 75,
  suv: 80,
  motorcycle: 35,
  bus: 185,
  rv: 185,
  truck2axle: 185,
  truck3axle: 280,
};

/**
 * Query Overpass API to find toll booths/plazas along a route bbox.
 * Uses the bounding box of the route to find OSM nodes tagged as toll booths.
 *
 * @param {{lat:number,lng:number}} start
 * @param {{lat:number,lng:number}} end
 * @returns {Promise<number>} count of toll plazas detected
 */
async function countTollsViaOSM(start, end) {
  // Build a bounding box with ~0.3 degree buffer around the route
  const minLat = Math.min(start.lat, end.lat) - 0.3;
  const maxLat = Math.max(start.lat, end.lat) + 0.3;
  const minLng = Math.min(start.lng, end.lng) - 0.3;
  const maxLng = Math.max(start.lng, end.lng) + 0.3;

  // Overpass query: find highway=toll_booth nodes in the bounding box
  const query = `
    [out:json][timeout:15];
    (
      node["highway"="toll_booth"](${minLat},${minLng},${maxLat},${maxLng});
      node["barrier"="toll_booth"](${minLat},${minLng},${maxLat},${maxLng});
    );
    out count;
  `;

  try {
    const response = await axios.post(
      "https://overpass-api.de/api/interpreter",
      `data=${encodeURIComponent(query)}`,
      {
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        timeout: 15000,
      }
    );

    const elements = response.data && response.data.elements;
    if (elements && elements.length > 0 && elements[0].tags && elements[0].tags.total) {
      return parseInt(elements[0].tags.total, 10) || 0;
    }
    // Fallback: count nodes in elements array
    return Array.isArray(elements) ? elements.length : 0;
  } catch (err) {
    console.error("OSM toll lookup failed:", err.message);
    return 0;
  }
}

/**
 * Estimate tolls using OSM data as a free fallback.
 * Returns hasTolls, currency, and estimated cost range based on toll plaza count.
 *
 * @param {{lat:number,lng:number}} start
 * @param {{lat:number,lng:number}} end
 * @param {string} vehicleKey
 * @returns {Promise<object>}
 */
async function getTollEstimateOSMFallback(start, end, vehicleKey = "car") {
  const tollCount = await countTollsViaOSM(start, end);
  const ratePerPlaza = INDIA_TOLL_RATE_PER_PLAZA[vehicleKey] || INDIA_TOLL_RATE_PER_PLAZA.car;

  if (tollCount === 0) {
    return {
      hasTolls: false,
      currency: "INR",
      minTollCost: 0,
      maxTollCost: 0,
      fuelCost: null,
      source: "osm",
    };
  }

  // Estimate: assume ~60-70% of toll booths in the bbox are actually on this specific route
  const estimatedPlazas = Math.max(1, Math.round(tollCount * 0.6));
  const minCost = estimatedPlazas * ratePerPlaza;
  const maxCost = Math.round(minCost * 1.3); // +30% upper bound

  return {
    hasTolls: true,
    currency: "INR",
    minTollCost: minCost,
    maxTollCost: maxCost,
    fuelCost: null,
    tollPlazaCount: estimatedPlazas,
    source: "osm",
  };
}

/**
 * Get toll + fuel cost estimate for a route.
 * First tries TollGuru (accurate, but rate-limited free tier).
 * Falls back to OSM-based estimation if TollGuru fails.
 *
 * @param {{lat:number,lng:number}} start
 * @param {{lat:number,lng:number}} end
 * @param {keyof VEHICLE_TYPES} vehicleKey
 * @returns {Promise<object|null>}
 */
async function getTollEstimate(start, end, vehicleKey = "car") {
  const apiKey = process.env.TOLLGURU_API_KEY;
  const vehicleType = VEHICLE_TYPES[vehicleKey] || VEHICLE_TYPES.car;

  // Try TollGuru first (most accurate)
  if (apiKey) {
    try {
      const response = await axios.post(
        TOLLGURU_URL,
        {
          from: { lat: start.lat, lng: start.lng },
          to: { lat: end.lat, lng: end.lng },
          vehicle: { type: vehicleType },
        },
        {
          headers: {
            "Content-Type": "application/json",
            "x-api-key": apiKey,
          },
          timeout: 15000,
        }
      );

      const route = response.data.routes && response.data.routes[0];
      if (route) {
        console.log("TollGuru succeeded:", JSON.stringify(route.summary));
        return {
          hasTolls: route.summary.hasTolls,
          currency: response.data.summary?.currency || "INR",
          minTollCost: route.costs.minimumTollCost,
          maxTollCost: route.costs.maximumTollCost,
          fuelCost: route.costs.fuel,
          source: "tollguru",
        };
      }
    } catch (err) {
      console.error(
        "TollGuru failed (falling back to OSM):",
        err.response ? JSON.stringify(err.response.data) : err.message
      );
    }
  }

  // Fallback: Use OSM toll booth data
  console.log("Using OSM fallback for toll estimation...");
  return await getTollEstimateOSMFallback(start, end, vehicleKey);
}

module.exports = { getTollEstimate, VEHICLE_TYPES };
