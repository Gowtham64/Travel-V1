/**
 * Pure geographic math helpers.
 * No network calls here on purpose - keeps this file fast and 100% unit-testable.
 */

const EARTH_RADIUS_KM = 6371.0088;

function toRad(deg) {
  return (deg * Math.PI) / 180;
}

/**
 * Great-circle distance between two {lat, lng} points, in kilometers.
 */
function haversineDistanceKm(a, b) {
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const lat1 = toRad(a.lat);
  const lat2 = toRad(b.lat);

  const sinDLat = Math.sin(dLat / 2);
  const sinDLng = Math.sin(dLng / 2);

  const h =
    sinDLat * sinDLat +
    Math.cos(lat1) * Math.cos(lat2) * sinDLng * sinDLng;

  const c = 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
  return EARTH_RADIUS_KM * c;
}

/**
 * Given an ordered list of {lat, lng} points describing a route, return the
 * same points annotated with cumulative distance from the start (in km).
 */
function annotateCumulativeDistance(points) {
  let cumulativeKm = 0;
  return points.map((point, index) => {
    if (index > 0) {
      cumulativeKm += haversineDistanceKm(points[index - 1], point);
    }
    return { ...point, cumulativeKm };
  });
}

module.exports = {
  haversineDistanceKm,
  annotateCumulativeDistance,
};
