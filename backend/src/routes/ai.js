const express = require("express");
const { recommendStops, searchPlaces, travelOptions, ask, buildItinerary, smartItinerary, listModels, AiConfigError, PROVIDER, ACTIVE_MODEL } = require("../services/aiService");
const { groundItinerary, geocode } = require("../services/itineraryGeo");

// Generous bounding box for India (mainland + islands). Used to decide whether
// a destination is domestic or international for budget pricing.
function isInIndia(pt) {
  return !!pt && pt.lat >= 6.5 && pt.lat <= 37.5 && pt.lng >= 68.0 && pt.lng <= 97.5;
}
const { estimateBudget } = require("../services/budgetService");
const priceService = require("../services/priceService");
const { calculateTripRoute } = require("../services/routeCalculationService");

const router = express.Router();

// Reports whether the AI key is configured and which model is in use (no secrets).
router.get("/status", (req, res) => {
  const keyByProvider = { gemini: process.env.GEMINI_API_KEY || process.env.GOOGLE_API_KEY, groq: process.env.GROQ_API_KEY, openrouter: process.env.OPENROUTER_API_KEY };
  res.json({
    provider: PROVIDER,
    model: ACTIVE_MODEL,
    configured: !!keyByProvider[PROVIDER],
  });
});

// Accept either a place-name string or a { lat, lng } coordinate object and
// always produce a clean prompt string. Prevents "[object Object]" from leaking
// into the AI prompt when the client sends coordinates instead of a name.
function toPlaceString(v) {
  if (v == null) return "";
  if (typeof v === "object") {
    const lat = v.lat ?? v.latitude;
    const lng = v.lng ?? v.lon ?? v.longitude;
    const name = v.name ? (typeof v.name === "object" ? (v.name.name || v.name.title || "") : String(v.name)) : "";
    if (name && name !== "[object Object]") return name;
    if (lat != null && lng != null && Number.isFinite(Number(lat)) && Number.isFinite(Number(lng))) return `${lat},${lng}`;
    return "";
  }
  const s = String(v).trim();
  return s === "[object Object]" ? "" : s;
}

function handleError(res, err) {
  if (err instanceof AiConfigError) {
    return res.status(503).json({ error: "AI is not configured on the server." });
  }
  const status = err.response ? err.response.status : 502;
  const upstream = err.response && err.response.data ? err.response.data : null;
  const upstreamMessage = upstream && upstream.error ? upstream.error.message : err.message;
  console.error("AI request failed:", err.message, JSON.stringify(upstream || {}));
  // A rate limit is temporary, not a server fault — tell the user clearly and
  // pass along the "try again in X" hint the provider gives, if any.
  if (status === 429) {
    const m = /try again in ([0-9hms.\s]+)/i.exec(upstreamMessage || "");
    return res.status(429).json({
      error: m
        ? `The AI is busy right now (daily limit reached). Please try again in ${m[1].trim()}.`
        : "The AI is busy right now (rate limit reached). Please try again in a few minutes.",
      upstreamStatus: 429,
    });
  }
  return res.status(502).json({
    error: "AI request failed",
    upstreamStatus: status,
    upstreamMessage,
    upstreamStatusText: upstream && upstream.error ? upstream.error.status : undefined,
  });
}

// Diagnostic: which models this key can use.
router.get("/models", async (req, res) => {
  try {
    res.json({ provider: PROVIDER, current: ACTIVE_MODEL, available: await listModels() });
  } catch (err) {
    handleError(res, err);
  }
});

// Recommend notable stops along a route.
router.post("/recommend", async (req, res) => {
  const { start, end, waypoints } = req.body || {};
  if (!start || !end) {
    return res.status(400).json({ error: "start and end are required" });
  }
  try {
    const places = await recommendStops({
      start: toPlaceString(start),
      end: toPlaceString(end),
      waypoints: (Array.isArray(waypoints) ? waypoints : []).map(toPlaceString).filter(Boolean),
    });
    res.json({ places });
  } catch (err) {
    handleError(res, err);
  }
});

// Natural-language place search.
router.post("/search", async (req, res) => {
  const { query, near } = req.body || {};
  if (!query || !String(query).trim()) {
    return res.status(400).json({ error: "query is required" });
  }
  try {
    const places = await searchPlaces({ query: String(query), near });
    res.json({ places });
  } catch (err) {
    handleError(res, err);
  }
});

// AI-suggested flight / train / hotel options for a journey (typical, not live).
router.post("/travel-options", async (req, res) => {
  const b = req.body || {};
  if (!b.to || !String(b.to).trim()) {
    return res.status(400).json({ error: "to (destination) is required" });
  }
  try {
    const options = await travelOptions({
      from: b.from ? String(b.from) : "",
      to: String(b.to),
      startDate: b.startDate ? String(b.startDate) : "",
      travellers: Math.max(1, Math.min(Number(b.travellers) || 1, 20)),
      nights: Math.max(0, Math.min(Number(b.nights) || 0, 60)),
    });
    res.json(options);
  } catch (err) {
    handleError(res, err);
  }
});

// Structured, day-by-day itinerary builder.
router.post("/itinerary", async (req, res) => {
  const { start, end, days, waypoints, travellers, purpose, startDate, startTime, startDateTime, timezone, weather } = req.body || {};
  if (!start || !end) {
    return res.status(400).json({ error: "start and end are required" });
  }
  try {
    let resolvedDate = startDate ? String(startDate) : "";
    let resolvedTime = startTime ? String(startTime) : "";
    if (startDateTime && (!resolvedDate || !resolvedTime)) {
      const dtParts = String(startDateTime).trim().split(/[T ]/);
      if (dtParts.length >= 1 && !resolvedDate) resolvedDate = dtParts[0];
      if (dtParts.length >= 2 && !resolvedTime) resolvedTime = dtParts[1];
    }

    const itinerary = await buildItinerary({
      start: toPlaceString(start),
      end: toPlaceString(end),
      days: Number(days) || 1,
      waypoints: (Array.isArray(waypoints) ? waypoints : []).map(toPlaceString).filter(Boolean),
      travellers: Number(travellers) || 1,
      purpose: purpose ? String(purpose) : "",
      startDate: resolvedDate,
      startTime: resolvedTime,
      timezone: timezone ? String(timezone) : "",
      weather: weather ? String(weather) : "",
    });
    res.json({ days: itinerary });
  } catch (err) {
    handleError(res, err);
  }
});

const itineraryEngine = require("../services/itineraryEngine");

function cleanObjectStrings(obj) {
  if (obj == null) return obj;
  if (typeof obj === "string") {
    if (obj === "[object Object]") return "";
    if (obj.includes("[object Object]")) {
      return obj.replace(/\[object Object\]/g, "").trim();
    }
    return obj;
  }
  if (Array.isArray(obj)) {
    return obj.map(cleanObjectStrings);
  }
  if (typeof obj === "object") {
    const res = {};
    for (const [k, v] of Object.entries(obj)) {
      res[k] = cleanObjectStrings(v);
    }
    return res;
  }
  return obj;
}

function normalizeLocationInput(loc) {
  if (!loc) return "";
  if (typeof loc === "object") {
    return itineraryEngine.normalizeCanonicalLocation(loc);
  }
  const clean = itineraryEngine.extractLocationName(loc, "");
  return clean || String(loc).trim();
}

// Smart, time-blocked itinerary with automatic breaks + per-block reasons.
router.post("/smart-itinerary", async (req, res) => {
  const b = req.body || {};
  if (!b.destination && !b.startLocation) {
    return res.status(400).json({ error: "destination or startLocation is required" });
  }
  try {
    const startLocation = normalizeLocationInput(b.startLocation) || normalizeLocationInput(b.destination);
    const destination = normalizeLocationInput(b.destination) || startLocation;
    let resolvedDate = b.startDate ? String(b.startDate) : "";
    let resolvedTime = b.startTime ? String(b.startTime) : "";
    if (b.startDateTime && (!resolvedDate || !resolvedTime)) {
      const dtParts = String(b.startDateTime).trim().split(/[T ]/);
      if (dtParts.length >= 1 && !resolvedDate) resolvedDate = dtParts[0];
      if (dtParts.length >= 2 && !resolvedTime) resolvedTime = dtParts[1];
    }
    if (!resolvedTime) resolvedTime = "08:00";

    const tripType = (b.tripType === "one_way" || b.tripType === "oneway") ? "one_way" : "around";
    const searchRadiusKm = Number(b.searchRadiusKm) > 0 ? Number(b.searchRadiusKm) : 25;
    const durationDays = Math.max(1, Math.min(Number(b.durationDays) || 1, 14));
    const vehicleType = String(b.vehicleType || "car").toLowerCase();
    const fuelEfficiency = Number(b.fuelEfficiency) > 0 ? Number(b.fuelEfficiency) : (vehicleType === "bike" ? 35 : 15);
    const tankCapacity = Number(b.tankCapacity) > 0 ? Number(b.tankCapacity) : (vehicleType === "bike" ? 13 : 45);
    const currentFuel = Number(b.currentFuel) > 0 ? Number(b.currentFuel) : tankCapacity * 0.7;

    // Execute the deterministic Itinerary Planning Engine
    const planResult = await itineraryEngine.planItinerary({
      startLocation,
      destination,
      tripType,
      startDate: resolvedDate,
      startTime: resolvedTime,
      startDateTime: b.startDateTime ? String(b.startDateTime) : "",
      timezone: b.timezone ? String(b.timezone) : "Asia/Kolkata",
      durationDays,
      mode: ["relaxed", "balanced", "packed"].includes(b.mode) ? b.mode : "balanced",
      places: (Array.isArray(b.places) ? b.places : []).map(String).filter(Boolean),
      selectedCategories: Array.isArray(b.selectedCategories) ? b.selectedCategories.map(String) : [],
      categoryPriorities: b.categoryPriorities && typeof b.categoryPriorities === "object" ? b.categoryPriorities : {},
      preferences: [b.preferences, b.customPreferences].filter(Boolean).join(". "),
      vehicle: {
        type: vehicleType,
        efficiencyKmPerLiter: fuelEfficiency,
        tankCapacityLiters: tankCapacity,
        currentFuelLiters: currentFuel,
      },
      travellers: Math.max(1, Math.min(Number(b.travellers) || 1, 20)),
      searchRadiusKm,
    });

    const days = planResult.days;

    // Full trip budget: fuel + tolls + transport tickets + local transport + food + stay.
    let budget = null;
    try {
      let groundKm = planResult.totalDistanceKm || 0;
      const transportLegs = [];
      let international = false;
      try {
        const destPt = await geocode(destination, "");
        if (destPt) international = !isInIndia(destPt);
      } catch (_) {}

      const driveKm = international ? 0 : groundKm;
      const localKm = international ? groundKm : 0;
      const rates = priceService.getRates();
      const tollGuess = Math.round(driveKm * rates.tollPerKm);

      budget = estimateBudget({
        driveKm: Math.round(driveKm),
        localTransportKm: Math.round(localKm),
        transportLegs,
        ticketRates: rates.ticketRates,
        estimatedDays: durationDays,
        vehicle: { efficiencyKmPerLiter: fuelEfficiency },
        toll: { hasTolls: tollGuess > 0, fastagTollCost: tollGuess },
        options: {
          international,
          travellers: Math.max(1, Math.min(Number(b.travellers) || 1, 20)),
          fuelPricePerLiter: Number(b.fuelPrice) > 0 ? Number(b.fuelPrice) : rates.fuel.petrolPerLiter,
          foodPerDay: international ? rates.intl.foodPerDay : rates.foodPerDay,
          stayPerNight: international ? rates.intl.stayPerNight : rates.stayPerNight,
          localTaxiPerKm: international ? rates.intl.localTaxiPerKm : rates.localTaxiPerKm,
        },
      });
    } catch (err) {
      console.error("Itinerary budget estimate skipped:", err.message);
    }

    res.json(cleanObjectStrings({
      days,
      budget: planResult.budget || budget,
      route: planResult.route || null,
      navigationRoute: planResult.navigationRoute || null,
      tripPlan: planResult.tripPlan || null,
      routeVersion: planResult.routeVersion || 1,
      tripType: planResult.tripType || "around",
      startPoint: planResult.startPoint,
      endPoint: planResult.endPoint,
      destinationPoint: planResult.destinationPoint,
      searchRadiusKm: planResult.searchRadiusKm,
      placesFoundCount: planResult.placesFoundCount,
      canExpandSearch: planResult.canExpandSearch,
      nextSearchRadiusKm: planResult.nextSearchRadiusKm,
      totalDistanceKm: planResult.totalDistanceKm,
      totalDurationMin: planResult.totalDurationMin,
      status: "DRAFT",
    }));
  } catch (err) {
    handleError(res, err);
  }
});

// Recalculate itinerary on user edits (add/remove stop, reorder, adjust duration, change start time)
router.post("/recalculate-itinerary", async (req, res) => {
  const b = req.body || {};
  const days = Array.isArray(b.days) ? b.days : [];
  if (days.length === 0) {
    return res.status(400).json({ error: "days array is required" });
  }

  try {
    const inputVersion = Number(b.routeVersion) || 1;
    const nextRouteVersion = inputVersion + 1;

    // 1. Extract start location, destination, and all intermediate stops
    let startPoint = null;
    let destPoint = null;
    const intermediateStops = [];

    // Check provided explicit strings or points
    if (b.origin || b.startLocation) {
      try {
        startPoint = await itineraryEngine.resolveLocation(normalizeLocationInput(b.origin || b.startLocation), "Origin");
      } catch (_) {}
    }
    if (b.destination) {
      try {
        destPoint = await itineraryEngine.resolveLocation(normalizeLocationInput(b.destination), "Destination", startPoint);
      } catch (_) {}
    }

    // Inspect blocks from all days
    for (const day of days) {
      const blocks = Array.isArray(day.blocks) ? day.blocks : [];
      for (const blk of blocks) {
        if (!startPoint && blk.type === "start" && blk.lat && blk.lng) {
          startPoint = { lat: blk.lat, lng: blk.lng, name: blk.place || blk.title, address: blk.address };
        }
        if (!destPoint && (blk.isDestination || blk.isDestinationAnchor) && blk.lat && blk.lng) {
          destPoint = { lat: blk.lat, lng: blk.lng, name: blk.place || blk.title, address: blk.address, placeId: blk.placeId };
        }
        // Only extract actual stopovers for routing (not meals/rest/coffee sharing coords)
        if (
          blk.lat && blk.lng &&
          (blk.type === "activity" || blk.type === "fuel" || blk.type === "attraction" || blk.isDestinationAnchor)
        ) {
          const isDup = intermediateStops.some((prev) => {
            const dLat = (prev.lat - blk.lat) * 111;
            const dLng = (prev.lng - blk.lng) * 111 * Math.cos((blk.lat * Math.PI) / 180);
            return Math.sqrt(dLat * dLat + dLng * dLng) < 0.1;
          });
          if (!isDup) {
            intermediateStops.push({
              id: blk.id,
              name: blk.place || blk.title,
              lat: blk.lat,
              lng: blk.lng,
              address: blk.address || blk.place || blk.title,
              type: blk.type,
              sequence: intermediateStops.length + 1,
              durationMin: blk.durationMin,
              stayDuration: blk.durationMin,
              category: blk.category,
              reason: blk.reason,
            });
          }
        }
      }
    }

    if (!startPoint && intermediateStops.length > 0) {
      startPoint = { lat: intermediateStops[0].lat, lng: intermediateStops[0].lng, name: intermediateStops[0].name };
    }
    if (!destPoint) {
      destPoint = intermediateStops.length > 0 ? intermediateStops[intermediateStops.length - 1] : startPoint;
    }

    // 2. Authoritative Route Calculation
    let routeCalc = null;
    if (startPoint && destPoint) {
      try {
        routeCalc = await calculateTripRoute({
          origin: startPoint,
          destination: destPoint,
          stops: intermediateStops,
          vehicle: {
            type: b.vehicleType || "car",
            efficiencyKmPerLiter: Number(b.fuelEfficiency) || 15,
            tankCapacityLiters: Number(b.tankCapacity) || 45,
            currentFuelLiters: Number(b.currentFuel) || 30,
          },
          tripType: b.tripType || "around",
          durationDays: days.length,
          travellers: Math.max(1, Math.min(Number(b.travellers) || 1, 20)),
          routeVersion: nextRouteVersion,
        });
      } catch (err) {
        console.warn("[RECALCULATE ITINERARY] Route calculation warning:", err.message);
      }
    }

    // 3. Synchronize block travel metrics with authoritative route legs if available
    if (routeCalc && routeCalc.route && Array.isArray(routeCalc.route.legs) && routeCalc.route.legs.length > 0) {
      const legs = routeCalc.route.legs;
      let legIdx = 0;
      for (const day of days) {
        const blocks = Array.isArray(day.blocks) ? day.blocks : [];
        for (const blk of blocks) {
          if ((blk.type === "travel" || blk.type === "return") && legIdx < legs.length) {
            const rLeg = legs[legIdx++];
            if (rLeg.distanceKm > 0) {
              blk.distanceKm = Math.round(rLeg.distanceKm * 10) / 10;
              blk.travelMin = Math.max(1, Math.round(rLeg.durationMin || (rLeg.durationSeconds / 60) || 5));
            }
          }
        }
      }
    }

    // 4. Re-anchor timing across all days
    let startMin = b.startTime ? itineraryEngine.parseMinutes(b.startTime) : itineraryEngine.parseMinutes(days[0].blocks?.[0]?.start || "08:00");
    let fallbackTotalKm = 0;

    for (let d = 0; d < days.length; d++) {
      const day = days[d];
      let cur = d === 0 ? startMin : 510; // 08:30 AM on Day 2+
      const blocks = Array.isArray(day.blocks) ? day.blocks : [];

      for (let i = 0; i < blocks.length; i++) {
        const blk = blocks[i];
        blk.day = d + 1;
        blk.sequence = i;

        if (blk.type === "travel" || blk.type === "return") {
          const travelDur = Math.max(1, Number(blk.travelMin) || Math.round(((Number(blk.distanceKm) || 15) / 50) * 60));
          blk.start = itineraryEngine.formatMinutes(cur);
          blk.end = itineraryEngine.formatMinutes(cur + travelDur);
          cur += travelDur;
          fallbackTotalKm += Number(blk.distanceKm) || 0;
        } else if (blk.type === "start") {
          blk.start = itineraryEngine.formatMinutes(cur);
          blk.end = itineraryEngine.formatMinutes(cur);
        } else {
          const dur = Math.max(5, Number(blk.durationMin) || 30);
          blk.start = itineraryEngine.formatMinutes(cur);
          blk.end = itineraryEngine.formatMinutes(cur + dur);
          cur += dur;
        }
      }
    }

    const authoritativeDistanceKm = routeCalc?.route?.distanceKm ?? (Math.round(fallbackTotalKm * 10) / 10);
    const authoritativeDurationMin = routeCalc?.route?.durationMin ?? (Math.round((fallbackTotalKm / 50) * 60));

    // Fallback budget if routeCalc failed
    let budget = routeCalc?.budget;
    if (!budget) {
      const rates = priceService.getRates();
      const eff = Number(b.fuelEfficiency) || 15;
      const tollGuess = Math.round(authoritativeDistanceKm * rates.tollPerKm);
      budget = estimateBudget({
        distanceKm: Math.round(authoritativeDistanceKm),
        driveKm: Math.round(authoritativeDistanceKm),
        localTransportKm: 0,
        transportLegs: [],
        ticketRates: rates.ticketRates,
        estimatedDays: days.length,
        vehicle: { efficiencyKmPerLiter: eff },
        toll: { hasTolls: tollGuess > 0, fastagTollCost: tollGuess },
        options: {
          travellers: Math.max(1, Math.min(Number(b.travellers) || 1, 20)),
          fuelPricePerLiter: rates.fuel.petrolPerLiter,
          foodPerDay: rates.foodPerDay,
          stayPerNight: rates.stayPerNight,
        },
      });
    }

    res.json(cleanObjectStrings({
      days,
      route: routeCalc?.route || null,
      navigationRoute: routeCalc?.navigationRoute || null,
      tripPlan: routeCalc?.tripPlan || null,
      totalDistanceKm: authoritativeDistanceKm,
      totalDurationMin: authoritativeDurationMin,
      budget,
      routeVersion: nextRouteVersion,
      status: b.isConfirmed ? "CONFIRMED" : "DRAFT",
    }));
  } catch (err) {
    handleError(res, err);
  }
});


// Trip assistant / itinerary writer (free-form text answer).
router.post("/ask", async (req, res) => {
  const { question, context } = req.body || {};
  if (!question || !String(question).trim()) {
    return res.status(400).json({ error: "question is required" });
  }
  try {
    const text = await ask({ question: String(question), context });
    res.json({ text });
  } catch (err) {
    handleError(res, err);
  }
});

module.exports = router;
