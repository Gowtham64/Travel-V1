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
 * Get toll + fuel cost estimate for a route.
 *
 * @param {{lat:number,lng:number}} start
 * @param {{lat:number,lng:number}} end
 * @param {keyof VEHICLE_TYPES} vehicleKey
 * @returns {Promise<{hasTolls:boolean, currency:string, minTollCost:number|null, maxTollCost:number|null, fuelCost:number|null, distanceKm:number, durationMin:number}|null>}
 *   Returns null if the API call fails (e.g. free quota exceeded) - callers should treat tolls as
 *   "unknown" rather than failing the whole trip plan.
 */
async function getTollEstimate(start, end, vehicleKey = "car") {
  const apiKey = process.env.TOLLGURU_API_KEY;
  if (!apiKey) {
    throw new Error("TOLLGURU_API_KEY is not set - get a free key at https://tollguru.com/dashboard");
  }

  const vehicleType = VEHICLE_TYPES[vehicleKey] || VEHICLE_TYPES.car;

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
    if (!route) return null;

    return {
      hasTolls: route.summary.hasTolls,
      currency: response.data.summary.currency,
      minTollCost: route.costs.minimumTollCost,
      maxTollCost: route.costs.maximumTollCost,
      fuelCost: route.costs.fuel,
      distanceKm: Math.round((route.summary.distance.value / 1000) * 10) / 10,
      durationMin: Math.round(route.summary.duration.value / 60),
    };
  } catch (err) {
    // Free tier is rate-limited (as low as ~15 requests/day on a personal key) - don't crash
    // the whole trip plan if tolls can't be fetched, just report them as unavailable.
    console.error("TollGuru request failed:", err.response ? err.response.data : err.message);
    return null;
  }
}

module.exports = { getTollEstimate, VEHICLE_TYPES };
