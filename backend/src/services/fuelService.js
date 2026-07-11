const { annotateCumulativeDistance } = require("../utils/geo");

/**
 * Maximum distance (km) the vehicle can travel on its current fuel.
 */
function calculateRangeKm(currentFuelLiters, efficiencyKmPerLiter) {
  if (currentFuelLiters < 0 || efficiencyKmPerLiter <= 0) {
    throw new Error("currentFuelLiters must be >= 0 and efficiencyKmPerLiter must be > 0");
  }
  return currentFuelLiters * efficiencyKmPerLiter;
}

/**
 * Walk along the route and figure out where the vehicle needs to refuel.
 *
 * @param {Array<{lat:number, lng:number}>} routeCoordinates - ordered points along the route
 * @param {number} currentFuelLiters - fuel in the tank at the start of the trip
 * @param {number} tankCapacityLiters - full tank capacity
 * @param {number} efficiencyKmPerLiter - vehicle fuel efficiency
 * @param {number} [safetyMarginRatio=0.8] - refuel once this fraction of the tank's range is used,
 *   so the driver never runs the tank down to empty before reaching a station
 * @returns {{ refuelStops: Array<{lat:number, lng:number, distanceFromStartKm:number}>, totalDistanceKm: number, needsRefuel: boolean }}
 */
function findRefuelStops(
  routeCoordinates,
  currentFuelLiters,
  tankCapacityLiters,
  efficiencyKmPerLiter,
  safetyMarginRatio = 0.8
) {
  if (!Array.isArray(routeCoordinates) || routeCoordinates.length < 2) {
    throw new Error("routeCoordinates must contain at least 2 points");
  }

  const annotated = annotateCumulativeDistance(routeCoordinates);
  const totalDistanceKm = annotated[annotated.length - 1].cumulativeKm;

  const startRangeKm = calculateRangeKm(currentFuelLiters, efficiencyKmPerLiter) * safetyMarginRatio;
  const fullTankRangeKm = calculateRangeKm(tankCapacityLiters, efficiencyKmPerLiter) * safetyMarginRatio;

  if (totalDistanceKm <= startRangeKm) {
    return { refuelStops: [], totalDistanceKm, needsRefuel: false };
  }

  const refuelStops = [];
  let nextThresholdKm = startRangeKm;

  for (let i = 0; i < annotated.length; i += 1) {
    const point = annotated[i];
    if (point.cumulativeKm >= nextThresholdKm) {
      refuelStops.push({
        lat: point.lat,
        lng: point.lng,
        distanceFromStartKm: Math.round(point.cumulativeKm * 10) / 10,
      });
      nextThresholdKm = point.cumulativeKm + fullTankRangeKm;
    }
  }

  return { refuelStops, totalDistanceKm, needsRefuel: refuelStops.length > 0 };
}

/**
 * Estimate how many driving days a trip needs.
 *
 * @param {number} durationMinutes - total driving duration from the routing API
 * @param {number} [dailyDrivingHours=7] - how many hours per day the driver wants to drive
 * @param {number} [extraStopHours=0] - extra hours to add for sightseeing/meal stops
 */
function estimateTripDays(durationMinutes, dailyDrivingHours = 7, extraStopHours = 0) {
  if (durationMinutes <= 0 || dailyDrivingHours <= 0) {
    throw new Error("durationMinutes and dailyDrivingHours must be > 0");
  }
  const totalHours = durationMinutes / 60 + extraStopHours;
  return Math.max(1, Math.ceil(totalHours / dailyDrivingHours));
}

module.exports = {
  calculateRangeKm,
  findRefuelStops,
  estimateTripDays,
};
