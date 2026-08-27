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

/**
 * Given a route already annotated with cumulative distance, find how far along
 * the route (in km from the start) a nearby point sits, by projecting it onto the
 * closest route SEGMENT (not just the nearest vertex). Segment projection is more
 * accurate than vertex snapping and, on self-intersecting/looping routes, better
 * distinguishes the outbound pass from the return pass. Also returns how far
 * off-route the point is (perpendicular distance to that segment).
 *
 * @param {Array<{lat:number,lng:number,cumulativeKm:number}>} annotatedRoute
 * @param {{lat:number,lng:number}} point
 * @returns {{ distanceFromStartKm:number, offRouteKm:number }}
 */
function nearestRouteDistanceKm(annotatedRoute, point) {
  if (annotatedRoute.length === 1) {
    return {
      distanceFromStartKm: annotatedRoute[0].cumulativeKm,
      offRouteKm: haversineDistanceKm(annotatedRoute[0], point),
    };
  }

  // Local equirectangular projection (km) around the query point — accurate
  // enough for the short segment lengths in a dense route polyline.
  const latRad = toRad(point.lat);
  const kmPerDegLat = 111.32;
  const kmPerDegLng = 111.32 * Math.cos(latRad);
  const toXY = (p) => ({ x: p.lng * kmPerDegLng, y: p.lat * kmPerDegLat });
  const P = toXY(point);

  let best = null;
  for (let i = 1; i < annotatedRoute.length; i += 1) {
    const a = annotatedRoute[i - 1];
    const b = annotatedRoute[i];
    const A = toXY(a);
    const B = toXY(b);
    const dx = B.x - A.x;
    const dy = B.y - A.y;
    const segLenSq = dx * dx + dy * dy;
    // Fraction of the segment where the perpendicular from P lands, clamped to [0,1].
    let t = segLenSq > 0 ? ((P.x - A.x) * dx + (P.y - A.y) * dy) / segLenSq : 0;
    if (t < 0) t = 0;
    else if (t > 1) t = 1;
    const projX = A.x + t * dx;
    const projY = A.y + t * dy;
    const offRouteKm = Math.hypot(P.x - projX, P.y - projY);
    if (best === null || offRouteKm < best.offRouteKm) {
      const segKm = b.cumulativeKm - a.cumulativeKm;
      best = { distanceFromStartKm: a.cumulativeKm + t * segKm, offRouteKm };
    }
  }
  return best;
}

module.exports = {
  haversineDistanceKm,
  annotateCumulativeDistance,
  nearestRouteDistanceKm,
};
