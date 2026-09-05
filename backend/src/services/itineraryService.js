const { annotateCumulativeDistance } = require("../utils/geo");

/**
 * Break a trip into driving days. Each day covers up to `dailyDrivingHours` of
 * driving; we assume a roughly constant average speed to map hours -> distance
 * and pick the route point nearest each day's end as the overnight location.
 *
 * @returns {Array<{ day:number, fromKm:number, toKm:number, distanceKm:number,
 *   driveHours:number, endLat:number, endLng:number, isFinal:boolean }>}
 */
function buildItinerary(routeCoordinates, durationMinutes, dailyDrivingHours = 7, totalRouteDistanceKm = null) {
  if (!Array.isArray(routeCoordinates) || routeCoordinates.length < 2 || durationMinutes <= 0) {
    return [];
  }

  const totalHours = durationMinutes / 60;
  const dayHours = dailyDrivingHours > 0 ? dailyDrivingHours : 7;

  // Single-day trip - no breakdown needed.
  if (totalHours <= dayHours) {
    return [];
  }

  const annotated = annotateCumulativeDistance(routeCoordinates);
  const haversineTotalKm = annotated[annotated.length - 1].cumulativeKm;
  const totalKm = (typeof totalRouteDistanceKm === "number" && totalRouteDistanceKm > 0)
    ? totalRouteDistanceKm
    : haversineTotalKm;

  // Distance scale factor between authoritative road distance and haversine coordinates
  const scale = haversineTotalKm > 0 ? (totalKm / haversineTotalKm) : 1.0;
  const avgSpeedKmh = totalKm / totalHours;

  const days = [];
  let dayIndex = 0;
  let fromKm = 0;

  while (fromKm < totalKm - 0.5) {
    const remainingKm = totalKm - fromKm;
    const dayKm = Math.min(dayHours * avgSpeedKmh, remainingKm);
    const toKm = fromKm + dayKm;

    // Map toKm back to coordinate progression for overnight stop finding
    const targetHaversineKm = toKm / scale;
    let endPt = annotated[annotated.length - 1];
    for (const p of annotated) {
      if (p.cumulativeKm >= targetHaversineKm) { endPt = p; break; }
    }

    const isFinal = toKm >= totalKm - 0.5;
    days.push({
      day: dayIndex + 1,
      fromKm: Math.round(fromKm * 10) / 10,
      toKm: Math.round((isFinal ? totalKm : toKm) * 10) / 10,
      distanceKm: Math.round((isFinal ? totalKm - fromKm : dayKm) * 10) / 10,
      driveHours: Math.round((dayKm / avgSpeedKmh) * 10) / 10,
      endLat: endPt.lat,
      endLng: endPt.lng,
      isFinal,
    });

    fromKm = toKm;
    dayIndex += 1;
    if (dayIndex > 60) break; // safety guard
  }

  return days;
}

module.exports = { buildItinerary };
