const express = require("express");
const priceService = require("../services/priceService");

const router = express.Router();

// GET /api/prices — the current cached price table + when it was last refreshed.
router.get("/", (_req, res) => {
  const p = priceService.getRates();
  res.json({ ...p, stale: priceService.isStale() });
});

// POST /api/prices/refresh — force an immediate refresh from live sources.
// Optionally guard with PRICE_ADMIN_TOKEN (sent as x-admin-token) when set.
router.post("/refresh", async (req, res) => {
  const adminToken = process.env.PRICE_ADMIN_TOKEN;
  if (adminToken && req.get("x-admin-token") !== adminToken) {
    return res.status(401).json({ error: "unauthorized" });
  }
  try {
    const p = await priceService.refresh();
    res.json({ refreshed: true, ...p });
  } catch (err) {
    res.status(500).json({ error: "refresh failed", detail: err.message });
  }
});

module.exports = router;
