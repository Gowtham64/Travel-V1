const express = require("express");
const { getRoute } = require("../services/routingService");
const { findRefuelStops, planStationRefuelStops, estimateTripDays } = require("../services/fuelService");
const { getTollEstimate } = require("../services/tollService");
const { findPlacesAlongRoute } = require("../services/placesService");
const { getRouteWeather, getDepartureAdvice, suggestRestStops } = require("../services/weatherService");
const { estimateBudget } = require("../services/budgetService");
const { buildItinerary } = require("../services/itineraryService");
const { getWikiPlaces } = require("../services/wikiService");
const { getDestinationEvents } = require("../services/eventsService");

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
    const route = await getRoute(start, end, waypoints, { avoidMotorways });

    const currentFuelLiters = vehicle.currentFuelLiters ?? vehicle.tankCapacityLiters;

    // Fetch real fuel stations along the route so refuel stops land on actual
    // petrol pumps. Best-effort: Overpass can be slow or rate-limited, so a
    // failure here just falls back to geometric refuel markers below.
    let fuelStations = [];
    try {
      fuelStations = await findPlacesAlongRoute(route.coordinates, "fuel");
    } catch (err) {
      console.error("Fuel-station lookup skipped:", err.message);
    }

    // Prefer snapping refuel stops to reachable real stations; if we found no
    // stations (or the planner throws), fall back to the geometric estimate so
    // the driver still gets refuel guidance.
    let fuelPlan;
    try {
      fuelPlan = fuelStations.length
        ? planStationRefuelStops(
            route.coordinates,
            fuelStations,
            currentFuelLiters,
            vehicle.tankCapacityLiters,
            vehicle.efficiencyKmPerLiter
          )
        : findRefuelStops(
            route.coordinates,
            currentFuelLiters,
            vehicle.tankCapacityLiters,
            vehicle.efficiencyKmPerLiter
          );
    } catch (err) {
      console.error("Station refuel planning failed, using geometric fallback:", err.message);
      fuelPlan = findRefuelStops(
        route.coordinates,
        currentFuelLiters,
        vehicle.tankCapacityLiters,
        vehicle.efficiencyKmPerLiter
      );
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

    // Suggested rest breaks based on total drive time (pure logic).
    let restStops = [];
    try {
      restStops = suggestRestStops(route.coordinates, route.durationMin);
    } catch (err) {
      console.error("Rest-stop suggestion skipped:", err.message);
    }

    // Multi-day breakdown (pure logic).
    let itinerary = [];
    try {
      itinerary = buildItinerary(route.coordinates, route.durationMin, dailyDrivingHours);
    } catch (err) {
      console.error("Itinerary build skipped:", err.message);
    }

    // Full trip budget builds on the numbers we already have, so it can't fail.
    let budget = null;
    try {
      budget = estimateBudget({
        distanceKm: route.distanceKm,
        estimatedDays: days,
        vehicle,
        toll,
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
        distanceKm: route.distanceKm,
        durationMin: route.durationMin,
        coordinates: route.coordinates,
        // True when expressways/motorways were excluded because the vehicle
        // (2-/3-wheeler) is legally barred from them.
        avoidedMotorways: avoidMotorways,
      },
      estimatedDays: days,
      fuel: fuelPlan,
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
    const { data, error } = await req.supabase.from('trips').select(`
      *,
      trip_stops (*)
    `).eq('user_id', user_id).order('created_at', { ascending: false });
    
    if (error) throw error;
    res.json(data);
  } catch (err) {
    console.error("Error fetching saved trips:", err.message);
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;

