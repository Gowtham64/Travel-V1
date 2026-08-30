const express = require("express");
const { geocodeAddress, suggestPlaces } = require("../services/geocodeService");

const router = express.Router();

// GET /api/geocode/suggest?q=dub  → up to 6 autocomplete suggestions.
// The client's Mapbox token is URL-restricted (browser only), so the native
// app proxies destination autocomplete through here.
router.get("/suggest", async (req, res) => {
  const query = req.query.q;
  if (!query || typeof query !== "string" || query.trim().length < 2) {
    return res.json({ suggestions: [] });
  }
  try {
    const suggestions = await suggestPlaces(query.trim(), 6);
    res.json({ suggestions });
  } catch (err) {
    console.error("Autocomplete failed:", err.message);
    res.json({ suggestions: [] });
  }
});

// GET /api/geocode?q=Bengaluru, India
router.get("/", async (req, res) => {
  const query = req.query.q;
  if (!query || typeof query !== "string" || query.trim().length === 0) {
    return res.status(400).json({ error: "query param ?q= is required" });
  }

  try {
    const result = await geocodeAddress(query.trim());
    if (!result) {
      return res.status(404).json({ error: "No location found for that query" });
    }
    res.json(result);
  } catch (err) {
    console.error("Geocoding failed:", err.message);
    res.status(502).json({ error: "Geocoding failed", detail: err.message });
  }
});

module.exports = router;
