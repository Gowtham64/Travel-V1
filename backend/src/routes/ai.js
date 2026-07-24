const express = require("express");
const { recommendStops, searchPlaces, ask, listModels, AiConfigError, GEMINI_MODEL } = require("../services/aiService");

const router = express.Router();

// Reports whether the AI key is configured and which model is in use (no secrets).
router.get("/status", (req, res) => {
  res.json({
    configured: !!(process.env.GEMINI_API_KEY || process.env.GOOGLE_API_KEY),
    model: GEMINI_MODEL,
  });
});

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
    res.json({ current: GEMINI_MODEL, available: await listModels() });
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
    const places = await recommendStops({ start, end, waypoints: Array.isArray(waypoints) ? waypoints : [] });
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
