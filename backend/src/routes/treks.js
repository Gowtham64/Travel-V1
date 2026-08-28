const express = require("express");
const { findTreksNear, getTrekGeometry } = require("../services/treksService");
const { getWikiPlaces } = require("../services/wikiService");

const router = express.Router();

/**
 * GET /api/treks/geometry?id=way/123
 *
 * Lazily fetch one trail's line geometry (kept out of the discovery list so that
 * stays fast). Returns { path: [{lat,lng}], lengthKm }.
 */
router.get("/geometry", async (req, res) => {
  const id = req.query.id;
  if (!id || typeof id !== "string") {
    return res.status(400).json({ error: "id query param is required (e.g. way/123)" });
  }
  try {
    const geom = await getTrekGeometry(id);
    res.json(geom);
  } catch (err) {
    console.error("Trek geometry failed:", err.message);
    res.status(502).json({ error: "Failed to load trek geometry", detail: err.message });
  }
});

/**
 * GET /api/treks?lat=..&lng=..&radius=..&limit=..
 *
 * AllTrails-style discovery: returns named hiking/trekking trails near a point,
 * nearest first, enriched (best-effort) with Wikipedia summaries/photos so cards
 * can show a description and image.
 */
router.get("/", async (req, res) => {
  const lat = parseFloat(req.query.lat);
  const lng = parseFloat(req.query.lng);
  const radius = req.query.radius != null ? parseFloat(req.query.radius) : undefined;
  const limit = req.query.limit != null ? parseInt(req.query.limit, 10) : undefined;

  if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
    return res.status(400).json({ error: "lat and lng query params are required numbers" });
  }

  try {
    const treks = await findTreksNear(lat, lng, radius, limit);

    // Best-effort: pull nearby Wikipedia places once and attach a description/photo
    // to any trek whose name matches, so cards aren't bare. Never let this fail the request.
    let wiki = [];
    try {
      wiki = await getWikiPlaces(lat, lng, Math.round((radius || 20000)), 15);
    } catch (err) {
      console.error("Trek wiki enrichment skipped:", err.message);
    }

    const enriched = treks.map((t) => {
      const match = wiki.find(
        (w) =>
          w.title &&
          (w.title.toLowerCase().includes(t.name.toLowerCase()) ||
            t.name.toLowerCase().includes(w.title.toLowerCase()))
      );
      return {
        ...t,
        description: match ? match.summary || null : null,
        imageUrl: match ? match.thumbnailUrl || null : null,
      };
    });

    res.json({ count: enriched.length, treks: enriched });
  } catch (err) {
    console.error("Trek discovery failed:", err.message);
    res.status(502).json({ error: "Failed to load treks", detail: err.message });
  }
});

module.exports = router;
