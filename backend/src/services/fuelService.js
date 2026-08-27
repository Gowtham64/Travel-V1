const { annotateCumulativeDistance, nearestRouteDistanceKm } = require("../utils/geo");

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
 * Plan refuel stops at REAL fuel stations along the route.
 *
 * Unlike {@link findRefuelStops} (which drops a marker at an arbitrary point on
 * the route once a fraction of range is used), this snaps each stop to an actual
 * petrol pump the vehicle can reach on the fuel it will have left, using the
 * classic greedy "gas station" strategy: from each fill point, drive to the
 * farthest reachable station, top up, and repeat until the destination is within
 * range. If a stretch has no station in reach, the plan flags it so the UI can
 * warn the driver instead of silently stranding them.
 *
 * @param {Array<{lat:number,lng:number}>} routeCoordinates - ordered route points
 * @param {Array<{id?:number,name?:string,lat:number,lng:number}>} stations - candidate fuel stations near the route
 * @param {number} currentFuelLiters - fuel in the tank at the start
 * @param {number} tankCapacityLiters - full tank capacity
 * @param {number} efficiencyKmPerLiter - vehicle fuel efficiency
 * @param {number} [safetyMarginRatio=0.85] - only ever plan to use this fraction of
 *   the available range before topping up, so the driver reaches the pump with a buffer
 * @returns {{ needsRefuel:boolean, totalDistanceKm:number, unreachable:boolean,
 *   refuelStops:Array<{lat:number,lng:number,distanceFromStartKm:number,name:string,
 *   stationId:(number|null),offRouteKm:number,fuelOnArrivalLiters:number}> }}
 */
function planStationRefuelStops(
  routeCoordinates,
  stations,
  currentFuelLiters,
  tankCapacityLiters,
  efficiencyKmPerLiter,
  safetyMarginRatio = 0.85
) {
  if (!Array.isArray(routeCoordinates) || routeCoordinates.length < 2) {
    throw new Error("routeCoordinates must contain at least 2 points");
  }

  const annotated = annotateCumulativeDistance(routeCoordinates);
  const totalDistanceKm = annotated[annotated.length - 1].cumulativeKm;

  const startRangeKm = calculateRangeKm(currentFuelLiters, efficiencyKmPerLiter);
  const fullRangeKm = calculateRangeKm(tankCapacityLiters, efficiencyKmPerLiter);

  // Reachable on the fuel already in the tank (with a safety buffer) — no stop needed.
  if (totalDistanceKm <= startRangeKm * safetyMarginRatio) {
    return { needsRefuel: false, totalDistanceKm, unreachable: false, refuelStops: [] };
  }

  // Project each station onto the route (distance-from-start) and order them.
  const along = (stations || [])
    .map((s) => {
      const snap = nearestRouteDistanceKm(annotated, s);
      return {
        id: s.id != null ? s.id : null,
        name: s.name || "Fuel station",
        lat: s.lat,
        lng: s.lng,
        distanceFromStartKm: snap.distanceFromStartKm,
        offRouteKm: snap.offRouteKm,
      };
    })
    .sort((a, b) => a.distanceFromStartKm - b.distanceFromStartKm);

  const refuelStops = [];
  let lastStopKm = 0;
  let rangeRemainingKm = startRangeKm; // true (un-buffered) range left from lastStopKm
  let unreachable = false;

  // Keep topping up until the destination sits within the current buffered range.
  while (lastStopKm + rangeRemainingKm * safetyMarginRatio < totalDistanceKm) {
    const reachKm = lastStopKm + rangeRemainingKm * safetyMarginRatio;
    // Stations strictly ahead of the last stop and reachable within the buffer.
    // The +0.5km guard stops us re-selecting a pump we're effectively already at.
    const candidates = along.filter(
      (s) => s.distanceFromStartKm > lastStopKm + 0.5 && s.distanceFromStartKm <= reachKm
    );
    if (candidates.length === 0) {
      // Nothing in reach before we'd run the buffer dry — flag and stop planning.
      unreachable = true;
      break;
    }
    // Greedy: drive to the farthest reachable station to minimise the number of stops.
    const chosen = candidates[candidates.length - 1];
    // The pump sits off the route, so reaching it also burns the detour distance —
    // count it so the reported fuel-on-arrival isn't optimistic.
    const detourKm = chosen.offRouteKm || 0;
    const legKm = chosen.distanceFromStartKm - lastStopKm + detourKm;
    const fuelOnArrivalLiters = Math.max(0, (rangeRemainingKm - legKm) / efficiencyKmPerLiter);

    refuelStops.push({
      lat: chosen.lat,
      lng: chosen.lng,
      distanceFromStartKm: Math.round(chosen.distanceFromStartKm * 10) / 10,
      name: chosen.name,
      stationId: chosen.id,
      offRouteKm: Math.round(chosen.offRouteKm * 100) / 100,
      fuelOnArrivalLiters: Math.round(fuelOnArrivalLiters * 10) / 10,
    });

    lastStopKm = chosen.distanceFromStartKm;
    rangeRemainingKm = fullRangeKm; // assume a full top-up at the pump
  }

  return { needsRefuel: refuelStops.length > 0, totalDistanceKm, unreachable, refuelStops };
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
  planStationRefuelStops,
  estimateTripDays,
};
