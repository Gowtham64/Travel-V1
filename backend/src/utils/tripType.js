/**
 * tripType.js
 * 
 * Authoritative trip type normalization and topological route classification.
 * Defines canonical trip type identifiers and helper predicates to prevent
 * accidental degradation of multi-destination, circuit, loop, or vacation routes.
 */

const TRIP_TYPES = Object.freeze({
  ONE_WAY: "one_way",
  ROUND_TRIP: "round_trip",
  AROUND: "around",
  MULTI_DEST: "multi_dest",
  CIRCUIT: "circuit",
  LOOP: "loop",
  VACATION: "vacation",
});

/**
 * Normalizes any user, UI, or API string to a canonical VoyPlan trip type.
 *
 * @param {string} rawType
 * @returns {string} One of TRIP_TYPES values
 */
function normalizeTripType(rawType) {
  if (!rawType || typeof rawType !== "string") {
    return TRIP_TYPES.ROUND_TRIP;
  }

  const clean = rawType.toLowerCase().trim().replace(/[\s_-]/g, "");

  if (clean === "oneway" || clean === "pointtopoint" || clean === "direct") {
    return TRIP_TYPES.ONE_WAY;
  }

  if (clean === "around" || clean === "aroundtrip") {
    return TRIP_TYPES.AROUND;
  }

  if (
    clean === "multidest" ||
    clean === "multidestination" ||
    clean === "multistop" ||
    clean === "multistops" ||
    clean === "sequential"
  ) {
    return TRIP_TYPES.MULTI_DEST;
  }

  if (clean === "circuit" || clean === "circuittrip") {
    return TRIP_TYPES.CIRCUIT;
  }

  if (clean === "loop" || clean === "looptrip") {
    return TRIP_TYPES.LOOP;
  }

  if (
    clean === "vacation" ||
    clean === "vacationtrip" ||
    clean === "holiday" ||
    clean === "multiday" ||
    clean === "itinerary"
  ) {
    return TRIP_TYPES.VACATION;
  }

  if (
    clean === "round" ||
    clean === "roundtrip" ||
    clean === "return"
  ) {
    return TRIP_TYPES.ROUND_TRIP;
  }

  return TRIP_TYPES.ROUND_TRIP;
}

/**
 * Checks whether a trip type returns to its origin point.
 *
 * One-Way (origin -> dest) and Multi-Destination (origin -> s1 -> s2 -> dest)
 * terminate at the destination and DO NOT return to origin.
 *
 * Round-trip, around, circuit, loop, and vacation return to origin.
 *
 * @param {string} tripType
 * @returns {boolean}
 */
function isReturnToOrigin(tripType) {
  const norm = normalizeTripType(tripType);
  return (
    norm === TRIP_TYPES.ROUND_TRIP ||
    norm === TRIP_TYPES.AROUND ||
    norm === TRIP_TYPES.CIRCUIT ||
    norm === TRIP_TYPES.LOOP ||
    norm === TRIP_TYPES.VACATION
  );
}

/**
 * Checks whether a trip type expects multiple intermediate destinations/stops.
 *
 * @param {string} tripType
 * @returns {boolean}
 */
function hasIntermediateWaypoints(tripType) {
  const norm = normalizeTripType(tripType);
  return (
    norm === TRIP_TYPES.MULTI_DEST ||
    norm === TRIP_TYPES.AROUND ||
    norm === TRIP_TYPES.CIRCUIT ||
    norm === TRIP_TYPES.LOOP ||
    norm === TRIP_TYPES.VACATION
  );
}

/**
 * Formats a canonical trip type for display.
 *
 * @param {string} tripType
 * @returns {string}
 */
function formatTripType(tripType) {
  const norm = normalizeTripType(tripType);
  switch (norm) {
    case TRIP_TYPES.ONE_WAY:
      return "One Way";
    case TRIP_TYPES.ROUND_TRIP:
      return "Round Trip";
    case TRIP_TYPES.MULTI_DEST:
      return "Multi-Destination";
    case TRIP_TYPES.CIRCUIT:
      return "Circuit";
    case TRIP_TYPES.LOOP:
      return "Loop";
    case TRIP_TYPES.VACATION:
      return "Vacation / Multi-Day";
    default:
      return "Trip";
  }
}

module.exports = {
  TRIP_TYPES,
  normalizeTripType,
  isReturnToOrigin,
  hasIntermediateWaypoints,
  formatTripType,
};
