const { getRoute, toPoint, haversineMeters } = require("./routingService");
const { estimateBudget } = require("./budgetService");
const { getTollEstimate } = require("./tollService");
const priceService = require("./priceService");

// Vehicle types barred from expressways/motorways in India
const MOTORWAY_BANNED_TYPES = new Set([
  "motorcycle",
  "bike",
  "two_wheeler",
  "2w",
  "three_wheeler",
  "3w",
  "auto",
  "autorickshaw",
]);

function isMotorwayBanned(vehicleType) {
  return MOTORWAY_BANNED_TYPES.has(String(vehicleType || "").toLowerCase());
}

/**
 * Clean and normalize a location object into canonical schema:
 * { id, name, latitude, longitude, lat, lng, placeId, address, type, sequence, arrivalTime, departureTime, stayDuration }
 */
function normalizeLocation(loc, defaultName = "Location", defaultType = "stop", sequence = 0) {
  if (!loc) return null;
  const pt = toPoint(loc);
  if (!pt) return null;

  const lat = pt.lat;
  const lng = pt.lng;
  const name = String(loc.name || loc.title || loc.place || defaultName).trim();
  const address = String(loc.address || loc.formattedAddress || name).trim();
  const placeId = loc.placeId ? String(loc.placeId).trim() : `place_${lat.toFixed(5)}_${lng.toFixed(5)}`;
  const id = loc.id ? String(loc.id).trim() : `stop_${sequence}_${Date.now()}`;
  const stayDuration = Number(loc.stayDuration ?? loc.durationMin) || 0;

  return {
    id,
    name,
    latitude: lat,
    longitude: lng,
    lat,
    lng,
    placeId,
    address,
    type: loc.type || defaultType,
    sequence: Number(loc.sequence ?? sequence),
    arrivalTime: loc.arrivalTime || loc.start || "",
    departureTime: loc.departureTime || loc.end || "",
    stayDuration,
    category: loc.category || "",
    reason: loc.reason || "",
  };
}

/**
 * Authoritative Single Source of Truth for Route Calculation across VoyPlan
 *
 * Responsible for:
 * - Origin & Destination integrity
 * - Intermediate stops sequence
 * - Multi-stop road routing (actual road distance in meters & km)
 * - Road duration in seconds & minutes
 * - Route geometry & coordinates
 * - Route legs synchronization
 * - Exact fuel cost based strictly on road distance
 * - Toll estimation
 * - Authoritative trip budget
 * - Navigation waypoints with all intermediate stops
 *
 * @param {Object} params
 * @param {Object} params.origin - { lat, lng, name, address, placeId }
 * @param {Object} params.destination - { lat, lng, name, address, placeId } (Mandatory primary destination)
 * @param {Array<Object>} [params.stops] - Ordered intermediate stops
 * @param {Object} [params.vehicle] - { type, efficiencyKmPerLiter, tankCapacityLiters, currentFuelLiters, fuelType }
 * @param {string} [params.tripType='around'] - 'around' | 'one_way'
 * @param {number} [params.durationDays=1]
 * @param {number} [params.travellers=1]
 * @param {number} [params.routeVersion=1]
 * @param {Object} [params.options] - Extra options (avoidMotorways, fuelPrice, tripId)
 * @returns {Promise<Object>} Authoritative route & budget response
 */
async function calculateTripRoute({
  origin,
  destination,
  stops = [],
  vehicle = {},
  tripType = "around",
  durationDays = 1,
  travellers = 1,
  routeVersion = 1,
  options = {},
}) {
  const normOrigin = normalizeLocation(origin, "Origin", "origin", 0);
  const normDest = normalizeLocation(destination, "Destination", "destination", (stops || []).length + 1);

  if (!normOrigin) {
    throw new Error("Invalid origin: valid coordinates (lat, lng) are required");
  }
  if (!normDest) {
    throw new Error("Invalid destination: valid coordinates (lat, lng) are required");
  }

  const isAroundTrip = tripType === "around";
  const normStops = (Array.isArray(stops) ? stops : [])
    .map((s, idx) => normalizeLocation(s, `Stop ${idx + 1}`, "activity", idx + 1))
    .filter(Boolean);

  // Determine complete navigation route endpoints and intermediate waypoints
  let routeStart;
  let routeEnd;
  let intermediateWaypoints = [];

  if (isAroundTrip) {
    // Around trip circuit: departs origin, traverses stops / destination, returns to origin
    routeStart = { lat: normOrigin.lat, lng: normOrigin.lng, name: normOrigin.name, address: normOrigin.address };
    routeEnd = { lat: normOrigin.lat, lng: normOrigin.lng, name: `Return to ${normOrigin.name}`, address: normOrigin.address };

    // Intermediate stops to visit
    const wps = [];
    for (const s of normStops) {
      // Avoid inserting origin if already at start
      if (haversineMeters(s, routeStart) > 100) {
        wps.push({
          lat: s.lat,
          lng: s.lng,
          name: s.name,
          address: s.address,
          placeId: s.placeId,
          type: s.type,
          id: s.id,
          sequence: s.sequence,
        });
      }
    }

    // Ensure primary destination is included if not already in stops
    const hasDestNear = wps.some((w) => haversineMeters(w, normDest) <= 500);
    if (!hasDestNear && haversineMeters(normDest, routeStart) > 500) {
      wps.push({
        lat: normDest.lat,
        lng: normDest.lng,
        name: normDest.name,
        address: normDest.address,
        placeId: normDest.placeId,
        type: "destination_anchor",
        id: normDest.id,
      });
    }

    intermediateWaypoints = wps;
  } else {
    // One-Way trip: origin -> stops -> destination
    routeStart = { lat: normOrigin.lat, lng: normOrigin.lng, name: normOrigin.name, address: normOrigin.address };
    routeEnd = { lat: normDest.lat, lng: normDest.lng, name: normDest.name, address: normDest.address };

    intermediateWaypoints = normStops
      .filter((s) => haversineMeters(s, routeStart) > 100 && haversineMeters(s, routeEnd) > 100)
      .map((s) => ({
        lat: s.lat,
        lng: s.lng,
        name: s.name,
        address: s.address,
        placeId: s.placeId,
        type: s.type,
        id: s.id,
        sequence: s.sequence,
      }));
  }

  // Vehicle parameters & motorway restriction
  const vehicleType = String(vehicle.type || "car").toLowerCase();
  const avoidMotorways = options.avoidMotorways ?? isMotorwayBanned(vehicleType);
  const efficiency = Number(vehicle.efficiencyKmPerLiter) > 0 ? Number(vehicle.efficiencyKmPerLiter) : (vehicleType === "bike" ? 35 : 15);
  const tankCapacity = Number(vehicle.tankCapacityLiters) > 0 ? Number(vehicle.tankCapacityLiters) : (vehicleType === "bike" ? 13 : 45);

  // Authoritative Road Routing Call
  console.log(`[ROUTE CALCULATION] Calculating authoritative road route for ${tripType} trip with ${intermediateWaypoints.length} intermediate stop(s)`);
  const routeResult = await getRoute(routeStart, routeEnd, intermediateWaypoints, { avoidMotorways });

  if (!routeResult || !Array.isArray(routeResult.coordinates) || routeResult.coordinates.length < 2) {
    throw new Error("Routing engine failed to compute a valid road route");
  }

  const distanceMeters = Math.max(0, Math.round(Number(routeResult.distanceMeters) || 0));
  const distanceKm = Math.round((distanceMeters / 1000) * 10) / 10;
  const durationSeconds = Math.max(0, Math.round(Number(routeResult.durationSeconds) || 0));
  const durationMin = Math.max(1, Math.round(durationSeconds / 60));

  // Toll estimation
  let toll = null;
  try {
    toll = await getTollEstimate(routeStart, routeEnd, vehicleType, routeResult.coordinates);
  } catch (err) {
    console.warn("[ROUTE CALCULATION] Toll estimate failed, using rate fallback:", err.message);
  }

  // Live or fallback fuel rates
  const rates = priceService.getRates();
  const fuelPrice = Number(options.fuelPrice) > 0 ? Number(options.fuelPrice) : rates.fuel.petrolPerLiter;

  // Authoritative Budget Calculation based strictly on final road distance
  let budget = null;
  try {
    budget = estimateBudget({
      distanceKm,
      driveKm: distanceKm,
      estimatedDays: Math.max(1, Number(durationDays) || 1),
      vehicle: {
        type: vehicleType,
        efficiencyKmPerLiter: efficiency,
        tankCapacityLiters: tankCapacity,
        currentFuelLiters: vehicle.currentFuelLiters,
        fuelType: vehicle.fuelType,
      },
      toll,
      startLocation: normOrigin.name,
      options: {
        travellers: Math.max(1, Math.min(Number(travellers) || 1, 20)),
        fuelPricePerLiter: fuelPrice,
        foodPerDay: rates.foodPerDay,
        stayPerNight: rates.stayPerNight,
      },
    });
  } catch (err) {
    console.error("[ROUTE CALCULATION] Budget estimation error:", err.message);
    const estFuel = Math.round((distanceKm / efficiency) * fuelPrice);
    const estToll = toll?.fastagTollCost || Math.round(distanceKm * rates.tollPerKm);
    const estStay = Math.max(0, (durationDays - 1)) * rates.stayPerNight;
    const estFood = durationDays * rates.foodPerDay * travellers;
    budget = {
      fuel: estFuel,
      tolls: estToll,
      food: estFood,
      stay: estStay,
      activities: 500,
      total: estFuel + estToll + estFood + estStay + 500,
      breakdown: { fuel: estFuel, tolls: estToll, food: estFood, stay: estStay, activities: 500 },
    };
  }

  // Assemble comprehensive navigation waypoints (all intermediate stops)
  const navigationWaypoints = intermediateWaypoints.map((w, idx) => ({
    id: w.id || `nav_wp_${idx + 1}`,
    name: w.name || `Stop ${idx + 1}`,
    latitude: w.lat,
    longitude: w.lng,
    lat: w.lat,
    lng: w.lng,
    placeId: w.placeId || "",
    address: w.address || w.name,
    type: w.type || "waypoint",
    sequence: idx + 1,
    isStopover: true, // Actual stopover, NOT a pass-through via point
  }));

  const tripId = options.tripId || `trip_${normDest.name.toLowerCase().replace(/[^a-z0-9]/g, "_")}_${Date.now()}`;

  const canonicalResponse = {
    tripId,
    origin: normOrigin,
    destination: normDest,
    tripType,
    stops: normStops,
    route: {
      distanceMeters,
      distanceKm,
      durationSeconds,
      durationMin,
      polyline: routeResult.geometry?.coordinates ? JSON.stringify(routeResult.geometry) : "",
      coordinates: routeResult.coordinates || [],
      geometry: routeResult.geometry || {
        type: "LineString",
        coordinates: (routeResult.coordinates || []).map((c) => [c.lng, c.lat]),
      },
      legs: routeResult.legs || [],
      steps: routeResult.steps || [],
      maneuvers: routeResult.maneuvers || [],
      avoidedMotorways: Boolean(routeResult.avoidedMotorways),
      provider: routeResult.provider || "authoritative",
    },
    budget: {
      fuel: budget?.fuel ?? budget?.breakdown?.fuel ?? 0,
      tolls: budget?.tolls ?? budget?.breakdown?.tolls ?? 0,
      food: budget?.food ?? budget?.breakdown?.food ?? 0,
      stay: budget?.stay ?? budget?.breakdown?.stay ?? 0,
      activities: budget?.activities ?? budget?.breakdown?.activities ?? 500,
      total: budget?.total ?? 0,
      breakdown: budget?.breakdown || budget,
    },
    navigationRoute: {
      origin: routeStart,
      destination: routeEnd,
      waypoints: navigationWaypoints,
      distanceKm,
      distanceMeters,
      durationMin,
      durationSeconds,
      coordinates: routeResult.coordinates || [],
      geometry: routeResult.geometry,
    },
    routeVersion: Number(routeVersion) || 1,
  };

  return canonicalResponse;
}

module.exports = {
  calculateTripRoute,
  normalizeLocation,
};
