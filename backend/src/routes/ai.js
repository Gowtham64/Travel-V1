const express = require("express");
const { recommendStops, searchPlaces, ask, buildItinerary, smartItinerary, listModels, AiConfigError, PROVIDER, ACTIVE_MODEL } = require("../services/aiService");
const { groundItinerary } = require("../services/itineraryGeo");
const { estimateBudget } = require("../services/budgetService");

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
    if (v.name) return String(v.name);
    if (lat != null && lng != null) return `${lat},${lng}`;
    return "";
  }
  return String(v);
}

function handleError(res, err) {
  if (err instanceof AiConfigError) {
    return res.status(503).json({ error: "AI is not configured on the server." });
  }
  const status = err.response ? err.response.status : 502;
  const upstream = err.response && err.response.data ? err.response.data : null;
  console.error("AI request failed:", err.message, JSON.stringify(upstream || {}));
  return res.status(502).json({
    error: "AI request failed",
    upstreamStatus: status,
    upstreamMessage: upstream && upstream.error ? upstream.error.message : err.message,
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

// Structured, day-by-day itinerary builder.
router.post("/itinerary", async (req, res) => {
  const { start, end, days, waypoints, travellers, purpose, startDate, startTime, weather } = req.body || {};
  if (!start || !end) {
    return res.status(400).json({ error: "start and end are required" });
  }
  try {
    const itinerary = await buildItinerary({
      start: toPlaceString(start),
      end: toPlaceString(end),
      days: Number(days) || 1,
      waypoints: (Array.isArray(waypoints) ? waypoints : []).map(toPlaceString).filter(Boolean),
      travellers: Number(travellers) || 1,
      purpose: purpose ? String(purpose) : "",
      startDate: startDate ? String(startDate) : "",
      startTime: startTime ? String(startTime) : "",
      weather: weather ? String(weather) : "",
    });
    res.json({ days: itinerary });
  } catch (err) {
    handleError(res, err);
  }
});

// Smart, time-blocked itinerary with automatic breaks + per-block reasons.
router.post("/smart-itinerary", async (req, res) => {
  const b = req.body || {};
  if (!b.destination) {
    return res.status(400).json({ error: "destination is required" });
  }
  try {
    const startLocation = b.startLocation ? String(b.startLocation) : "";
    const days = await smartItinerary({
      destination: String(b.destination),
      startLocation,
      places: (Array.isArray(b.places) ? b.places : []).map(String).filter(Boolean),
      startDate: b.startDate ? String(b.startDate) : "",
      startTime: b.startTime ? String(b.startTime) : "08:00",
      endDate: b.endDate ? String(b.endDate) : "",
      endTime: b.endTime ? String(b.endTime) : "",
      durationDays: Math.max(1, Math.min(Number(b.durationDays) || 1, 14)),
      mode: ["relaxed", "balanced", "packed"].includes(b.mode) ? b.mode : "balanced",
      preferences: b.preferences ? String(b.preferences) : "",
      directive: b.directive ? String(b.directive) : "",
    });
    // Replace AI-estimated travel legs with real geocoded + routed distance/time
    // (best-effort; keeps AI numbers for any leg that can't be resolved).
    try {
      await groundItinerary(days, startLocation, String(b.destination));
    } catch (err) {
      console.error("Itinerary distance grounding skipped:", err.message);
    }

    // Full trip budget: fuel (from total drive distance) + tolls + food + stay.
    let budget = null;
    try {
      let totalKm = 0;
      for (const day of days) {
        for (const blk of day.blocks || []) {
          if (blk.type !== "travel" && blk.type !== "return") continue;
          // Fuel & tolls apply only to legs the traveller actually drives.
          // Flight/train/bus/ferry legs are not petrol/toll costs for the car.
          const mode = String(blk.travelMode || "drive").toLowerCase();
          if (mode === "drive" || mode === "walk") totalKm += Number(blk.distanceKm) || 0;
        }
      }
      const durationDays = Math.max(1, Math.min(Number(b.durationDays) || days.length || 1, 14));
      const eff = Number(b.fuelEfficiency) > 0 ? Number(b.fuelEfficiency) : 15;
      // Rough toll estimate (~₹0.7/km of driving) since we have no per-road toll data here.
      const tollGuess = Math.round(totalKm * 0.7);
      budget = estimateBudget({
        distanceKm: Math.round(totalKm),
        estimatedDays: durationDays,
        vehicle: { efficiencyKmPerLiter: eff },
        toll: { hasTolls: tollGuess > 0, fastagTollCost: tollGuess },
        options: {
          travellers: Math.max(1, Math.min(Number(b.travellers) || 1, 20)),
          ...(Number(b.fuelPrice) > 0 ? { fuelPricePerLiter: Number(b.fuelPrice) } : {}),
        },
      });
    } catch (err) {
      console.error("Itinerary budget estimate skipped:", err.message);
    }

    res.json({ days, budget });
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
