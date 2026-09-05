const express = require("express");
const { getRoute } = require("../services/routingService");
const { findRefuelStops, planStationRefuelStops, estimateTripDays, calculateRouteFuel, getFuelPrices } = require("../services/fuelService");
const { FuelRangeService } = require("../services/fuelRangeService");
const { getTollEstimate } = require("../services/tollService");
const { findPlacesAlongRoute } = require("../services/placesService");
const { getRouteWeather, getDepartureAdvice, suggestRestStops } = require("../services/weatherService");
const { estimateBudget } = require("../services/budgetService");
const { buildItinerary } = require("../services/itineraryService");
const { getWikiPlaces } = require("../services/wikiService");
const { getDestinationEvents } = require("../services/eventsService");
const { annotateCumulativeDistance, nearestRouteDistanceKm } = require("../utils/geo");

const router = express.Router();

function isValidPoint(p) {
  return p && typeof p.lat === "number" && typeof p.lng === "number";
}

// Vehicle types legally barred from access-controlled expressways/motorways in
// India (2-wheelers and 3-wheelers). Routes for these must avoid motorways.
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
 * POST /api/trip/plan
 *
 * Body:
 * {
 *   "start": { "lat": 12.9716, "lng": 77.5946 },
 *   "end":   { "lat": 13.0827, "lng": 80.2707 },
 *   "vehicle": {
 *     "type": "car",                 // car | suv | motorcycle | bus | rv | truck2axle | truck3axle
 *     "efficiencyKmPerLiter": 15,
 *     "tankCapacityLiters": 40,
 *     "currentFuelLiters": 30
 *   },
 *   "dailyDrivingHours": 7,          // optional, default 7
 *   "includePlaces": ["restaurant", "hotel"]   // optional, subset of fuel|hotel|restaurant|attraction
 * }
 */
router.post("/plan", async (req, res) => {
  const { start, end, waypoints = [], vehicle, dailyDrivingHours = 7, includePlaces = [], departAt = null } = req.body || {};

  if (!isValidPoint(start) || !isValidPoint(end)) {
    return res.status(400).json({ error: "start and end must be { lat, lng } objects" });
  }
  // Waypoints must be an array of valid points; otherwise the coordinate spread
  // below throws or the routing provider rejects it, surfacing as a vague 502.
  if (!Array.isArray(waypoints) || !waypoints.every(isValidPoint)) {
    return res.status(400).json({ error: "waypoints must be an array of { lat, lng } objects" });
  }
  if (!vehicle || !vehicle.efficiencyKmPerLiter || !vehicle.tankCapacityLiters) {
    return res.status(400).json({
      error: "vehicle must include efficiencyKmPerLiter and tankCapacityLiters",
    });
  }
  // Guard against non-positive numbers, which make the fuel/day math throw and
  // would otherwise surface as a confusing 502 instead of a clear 400.
  if (
    !(vehicle.efficiencyKmPerLiter > 0) ||
    !(vehicle.tankCapacityLiters > 0) ||
    (vehicle.currentFuelLiters != null && vehicle.currentFuelLiters < 0)
  ) {
    return res.status(400).json({
      error: "vehicle efficiencyKmPerLiter and tankCapacityLiters must be positive numbers",
    });
  }

  try {
    const avoidMotorways = isMotorwayBanned(vehicle.type);
    let route = await getRoute(start, end, waypoints, { avoidMotorways });

    const currentFuelLiters = vehicle.currentFuelLiters ?? vehicle.tankCapacityLiters;

    // Fetch real fuel stations along the route so refuel stops land on actual
    // petrol pumps. Best-effort: Overpass can be slow or rate-limited, so a
    // failure here just falls back to geometric refuel markers.
    let fuelStations = [];
    try {
      fuelStations = await findPlacesAlongRoute(route.coordinates, "fuel");
    } catch (err) {
      console.error("Fuel-station lookup skipped:", err.message);
    }

    // Execute smart refuel stop planning with safety reserve and location pricing
    let fuelPlan;
    try {
      fuelPlan = FuelRangeService.planSmartRefuelStops({
        routeCoordinates: route.coordinates,
        userStops: waypoints,
        stations: fuelStations,
        vehicle: {
          currentFuelLiters,
          tankCapacityLiters: vehicle.tankCapacityLiters,
          efficiencyKmPerLiter: vehicle.efficiencyKmPerLiter,
          fuelType: vehicle.fuelType,
        },
        options: {
          totalRouteDistanceKm: route.distanceKm,
        },
      });
    } catch (err) {
      console.error("Smart refuel planning error, using fallback:", err.message);
      fuelPlan = findRefuelStops(
        route.coordinates,
        currentFuelLiters,
        vehicle.tankCapacityLiters,
        vehicle.efficiencyKmPerLiter
      );
    }

    // Build ordered navigation waypoints merging user waypoints and system fuel stops.
    // CRITICAL: User waypoints MUST strictly maintain their user-selected itinerary order!
    // NEVER sort user waypoints against each other by distance.
    let navigationWaypoints = [];
    if (fuelPlan && Array.isArray(fuelPlan.refuelStops) && fuelPlan.refuelStops.length > 0) {
      console.log(`[FUEL] Stop calculated: ${fuelPlan.refuelStops.length} stop(s) required`);
      const annotated = annotateCumulativeDistance(route.coordinates);

      const userWpItems = (waypoints || []).map((wp, idx) => {
        const proj = nearestRouteDistanceKm(annotated, wp);
        return {
          ...wp,
          type: 'waypoint',
          name: wp.name || `Stop ${idx + 1}`,
          distanceFromStartKm: proj.distanceFromStartKm,
          userIndex: idx,
        };
      });

      const fuelWpItems = fuelPlan.refuelStops.map((fs) => ({
        ...fs,
        type: 'fuel_stop',
        name: fs.name || 'Fuel Station',
        isFuelStop: true,
      }));

      // Insert fuel stops strictly within their assigned leg (legIndex) to maintain
      // user waypoint sequence integrity and avoid false inversions on circuits.
      const combined = [];
      for (let i = 0; i < userWpItems.length; i++) {
        const legFuelStops = fuelWpItems
          .filter((f) => f.legIndex === i)
          .sort((a, b) => a.distanceFromStartKm - b.distanceFromStartKm);
        combined.push(...legFuelStops);
        combined.push(userWpItems[i]);
      }
      const finalLegFuelStops = fuelWpItems
        .filter((f) => f.legIndex === userWpItems.length)
        .sort((a, b) => a.distanceFromStartKm - b.distanceFromStartKm);
      combined.push(...finalLegFuelStops);

      navigationWaypoints = combined;

      // Re-route geometry through combined waypoints so polyline drives to fuel stations
      try {
        fuelPlan.refuelStops.forEach((s) => {
          console.log(`[FUEL] Stop added to navigation waypoints: ${s.name} (${s.lat}, ${s.lng}) at km ${s.distanceFromStartKm}`);
        });

        const routeWaypoints = combined.map((w) => ({ lat: w.lat, lng: w.lng, name: w.name }));
        const detourRoute = await getRoute(start, end, routeWaypoints, { avoidMotorways });
        if (detourRoute && Array.isArray(detourRoute.coordinates) && detourRoute.coordinates.length >= 2) {
          route = detourRoute;
        }
      } catch (err) {
        console.warn("[FUEL] Re-routing through fuel stops skipped, retaining direct route:", err.message);
      }
    } else {
      navigationWaypoints = (waypoints || []).map((wp, idx) => ({
        ...wp,
        type: 'waypoint',
        name: wp.name || `Stop ${idx + 1}`,
      }));
    }

    // estimateTripDays throws on non-positive inputs. A very short route rounds
    // to durationMin 0, and a client can pass dailyDrivingHours 0 — neither
    // should 502 the whole plan, so clamp to sane minimums and fall back to 1 day.
    let days = 1;
    try {
      const safeDuration = route.durationMin > 0 ? route.durationMin : 1;
      const safeDailyHours = dailyDrivingHours > 0 ? dailyDrivingHours : 7;
      days = estimateTripDays(safeDuration, safeDailyHours);
    } catch (err) {
      console.error("Trip-days estimate failed, defaulting to 1:", err.message);
    }

    // Toll lookup is best-effort - the free tier has a tiny daily quota, so a failure
    // here should not break the rest of the trip plan.
    let toll = null;
    try {
      toll = await getTollEstimate(start, end, vehicle.type, route.coordinates);
    } catch (err) {
      console.error("Toll lookup skipped:", err.message);
    }

    // Weather along the route is best-effort (free key-less API) - never let a
    // slow/failed weather call break the trip plan.
    let weather = null;
    try {
      weather = await getRouteWeather(route.coordinates);
    } catch (err) {
      console.error("Weather lookup skipped:", err.message);
    }

    // Best-departure advice (hourly rain at the start) — best-effort.
    let departureAdvice = null;
    try {
      departureAdvice = await getDepartureAdvice(start, 12, departAt);
    } catch (err) {
      console.error("Departure advice skipped:", err.message);
    }

    // Suggested rest breaks based on total drive time (pure logic) using authoritative distance.
    let restStops = [];
    try {
      restStops = suggestRestStops(route.coordinates, route.durationMin, 2.5, route.distanceKm);
    } catch (err) {
      console.error("Rest-stop suggestion skipped:", err.message);
    }

    // Multi-day breakdown (pure logic) using authoritative route distance.
    let itinerary = [];
    try {
      itinerary = buildItinerary(route.coordinates, route.durationMin, dailyDrivingHours, route.distanceKm);
    } catch (err) {
      console.error("Itinerary build skipped:", err.message);
    }

    // Fuel estimate derived from authoritative route distance, vehicle efficiency & live price
    let fuelEstimate = null;
    try {
      fuelEstimate = calculateRouteFuel({
        distanceKm: route.distanceKm,
        vehicleEfficiency: vehicle.efficiencyKmPerLiter,
        currentFuelLiters: vehicle.currentFuelLiters,
        tankCapacityLiters: vehicle.tankCapacityLiters,
        fuelType: vehicle.fuelType,
        startLocation: start?.name || '',
        endLocation: end?.name || '',
        routeCoordinates: route.coordinates,
      });
    } catch (err) {
      console.error("Fuel estimate calculation error:", err.message);
    }

    // Full trip budget builds on the numbers we already have, so it can't fail.
    let budget = null;
    try {
      budget = estimateBudget({
        distanceKm: route.distanceKm,
        estimatedDays: days,
        vehicle,
        toll,
        startLocation: start?.name || '',
        options: req.body.travellers ? { travellers: req.body.travellers } : {},
      });
    } catch (err) {
      console.error("Budget estimate skipped:", err.message);
    }

    // POI lookups are opt-in per request since each one is a separate Overpass call.
    const places = {};
    for (const category of includePlaces) {
      // Reuse the fuel stations already fetched for refuel planning instead of
      // hitting Overpass a second time for the same corridor.
      if (category === "fuel") {
        places.fuel = fuelStations;
        continue;
      }
      try {
        places[category] = await findPlacesAlongRoute(route.coordinates, category);
      } catch (err) {
        console.error(`Places lookup failed for ${category}:`, err.message);
        places[category] = [];
      }
    }

    // Fetch Wikipedia attraction summaries/photos near destination (best effort)
    let wikiAttractions = [];
    try {
      wikiAttractions = await getWikiPlaces(end.lat, end.lng, 10000, 5);
    } catch (err) {
      console.error("Wikipedia attractions lookup skipped:", err.message);
    }

    // Fetch upcoming local events near destination (best effort)
    let events = [];
    try {
      events = await getDestinationEvents(end.lat, end.lng, req.body.destinationName || "");
    } catch (err) {
      console.error("Events lookup skipped:", err.message);
    }

    res.json({
      route: {
        origin: { ...(route.origin || {}), ...(start || {}), lat: route.origin?.lat ?? start.lat, lng: route.origin?.lng ?? start.lng, name: route.origin?.name || start?.name },
        destination: { ...(route.destination || {}), ...(end || {}), lat: route.destination?.lat ?? end.lat, lng: route.destination?.lng ?? end.lng, name: route.destination?.name || end?.name },
        waypoints: route.waypoints || waypoints,
        coordinates: route.coordinates,
        geometry: route.geometry,
        distanceMeters: route.distanceMeters,
        distanceKm: route.distanceKm,
        durationSeconds: route.durationSeconds,
        durationMin: route.durationMin,
        legs: route.legs,
        steps: route.steps,
        maneuvers: route.maneuvers,
        avoidedMotorways: avoidMotorways,
        provider: route.provider,
      },
      estimatedDays: days,
      fuel: fuelPlan,
      fuelEstimate: fuelEstimate,
      navigationWaypoints,
      toll,
      weather,
      departureAdvice,
      restStops,
      itinerary,
      budget,
      places,
      wikiAttractions,
      events,
    });
  } catch (err) {
    console.error("Trip planning failed:", err.message);
    if (err.response && err.response.data) {
      console.error("ORS Error Detail:", JSON.stringify(err.response.data));
      return res.status(502).json({ error: "Failed to plan trip", detail: err.response.data.error?.message || JSON.stringify(err.response.data) });
    }
    res.status(502).json({ error: "Failed to plan trip", detail: err.message });
  }
});

const axios = require("axios");

router.get("/reverse-geocode", async (req, res) => {
  const { lat, lng } = req.query;
  if (!lat || !lng) return res.status(400).json({ error: "Missing lat or lng" });

  const MAPBOX_TOKEN = process.env.MAPBOX_TOKEN || "";
  try {
    // Mapbox reverse geocoding — reliable from cloud IPs (Nominatim 429s).
    // Missing token falls through to the Nominatim fallback below.
    if (!MAPBOX_TOKEN) throw new Error("MAPBOX_TOKEN not configured");
    const url = `https://api.mapbox.com/geocoding/v5/mapbox.places/${lng},${lat}.json?access_token=${MAPBOX_TOKEN}&limit=1&language=en`;
    const response = await axios.get(url, { timeout: 8000 });
    const feature = response.data?.features?.[0];
    res.json({ address: feature ? feature.place_name : null });
  } catch (err) {
    // Fall back to Nominatim with a descriptive UA.
    try {
      const url = `https://nominatim.openstreetmap.org/reverse?lat=${lat}&lon=${lng}&format=json&zoom=18`;
      const response = await axios.get(url, {
        headers: {
          "User-Agent": "TravelV1/1.0 (https://gowtham64.github.io/Travel-V1/)",
        },
        timeout: 5000,
      });
      res.json({ address: response.data?.display_name || null });
    } catch (err2) {
      console.error("Reverse geocoding failed:", err2.message);
      res.status(500).json({ error: "Reverse geocoding failed", detail: err2.message });
    }
  }
});

const { findPOIsAlongRoute } = require("../services/orsPoiService");

router.post("/pois", async (req, res) => {
  const { coordinates, categories } = req.body || {};
  
  if (!coordinates || !Array.isArray(coordinates)) {
    return res.status(400).json({ error: "coordinates must be an array of {lat, lng}" });
  }
  if (!categories || !Array.isArray(categories)) {
    return res.status(400).json({ error: "categories must be an array of strings" });
  }

  try {
    const places = await findPOIsAlongRoute(coordinates, categories);
    res.json({ places });
  } catch (err) {
    console.error("Failed to fetch POIs:", err.message);
    res.status(502).json({ error: "Failed to fetch POIs", detail: err.message });
  }
});

const { supabase } = require("../services/dbService");
const { requireAuth } = require("../utils/authMiddleware");

router.post("/save", requireAuth, async (req, res) => {
  if (!req.supabase) return res.status(503).json({ error: "Supabase not configured" });
  
  const user_id = req.user?.id;
  if (!user_id) return res.status(401).json({ error: "Unauthorized" });

  const { name, startPoint, endPoint, vehicleType, vehicle, waypoints, tripStart, itinerary } = req.body;

  try {
    // Persist the planned start, AI itinerary, and full vehicle spec inside the
    // existing end_point JSONB column, so no database migration/new columns are
    // required.
    const enrichedEnd = { ...(endPoint || {}) };
    if (tripStart) enrichedEnd.tripStart = tripStart;
    if (itinerary && itinerary.length) enrichedEnd.itinerary = itinerary;
    if (vehicle && typeof vehicle === "object") enrichedEnd.vehicle = vehicle;

    const { data, error } = await req.supabase.from('trips').insert({
      user_id,
      // Stamp the account email so the trip is visible from the user's other
      // sign-in identities (Google / email / phone). A DB trigger also fills
      // this in, so this is belt-and-suspenders.
      ...(req.user?.email ? { owner_email: String(req.user.email).toLowerCase() } : {}),
      name,
      start_point: startPoint,
      end_point: enrichedEnd,
      vehicle_type: vehicleType || 'car',
    }).select().single();
    if (error) throw error;
    
    // insert waypoints if any
    if (waypoints && waypoints.length > 0) {
      const stopsToInsert = waypoints.map((wp, i) => ({
        trip_id: data.id,
        type: wp.type || 'waypoint',
        lat: wp.lat,
        lng: wp.lng,
        name: wp.name,
        order_index: i
      }));
      const { error: stopsError } = await req.supabase.from('trip_stops').insert(stopsToInsert);
      // Don't leave a half-saved trip (a trip row with no stops). Roll back the
      // parent so the client can retry cleanly instead of silently losing stops.
      if (stopsError) {
        await req.supabase.from('trips').delete().eq('id', data.id);
        throw stopsError;
      }
    }

    res.json(data);
  } catch (err) {
    console.error("Error saving trip:", err.message);
    res.status(500).json({ error: err.message });
  }
});

router.get("/saved", requireAuth, async (req, res) => {
  if (!req.supabase) return res.status(503).json({ error: "Supabase not configured" });
  
  const user_id = req.user?.id;
  if (!user_id) return res.status(401).json({ error: "Unauthorized" });
  
  try {
    // No user_id filter: RLS returns every trip owned by this account (matched
    // by user_id OR the account's verified email), so trips saved from another
    // device/sign-in method sync in instead of being re-hidden.
    const { data, error } = await req.supabase.from('trips').select(`
      *,
      trip_stops (*)
    `).order('created_at', { ascending: false });
    
    if (error) throw error;
    // Filter out soft-deleted trips
    const active = (data || []).filter(t => t.status !== 'DELETED' && !t.deleted_at);
    res.json(active);
  } catch (err) {
    console.error("Error fetching saved trips:", err.message);
    res.status(500).json({ error: err.message });
  }
});

/**
 * DELETE /api/trip/:id
 * Soft-deletes a trip (sets status='DELETED', deleted_at) and cascades deletion.
 */
router.delete("/:id", requireAuth, async (req, res) => {
  if (!req.supabase) return res.status(503).json({ error: "Supabase not configured" });
  const { id } = req.params;
  if (!id) return res.status(400).json({ error: "Trip ID is required" });

  try {
    const nowIso = new Date().toISOString();
    // Try updating status/deleted_at first for audit/tombstone
    const { error: updateError } = await req.supabase
      .from("trips")
      .update({ status: "DELETED", deleted_at: nowIso })
      .eq("id", id);

    // If update succeeds or fails (e.g. column not yet migrated), also delete row to ensure clean removal
    const { error: deleteError } = await req.supabase
      .from("trips")
      .delete()
      .eq("id", id);

    if (updateError && deleteError) {
      throw deleteError || updateError;
    }

    res.json({ success: true, id, status: "DELETED", deleted_at: nowIso });
  } catch (err) {
    console.error("Error deleting trip:", err.message);
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;

