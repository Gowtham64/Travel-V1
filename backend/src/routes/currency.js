const express = require("express");
const axios = require("axios");

const router = express.Router();

// Simple in-memory rate cache (per base) to avoid hammering the free API.
const cache = new Map(); // base -> { at, rates }
const TTL_MS = 60 * 60 * 1000; // 1 hour

async function getRates(base) {
  const now = Date.now();
  const hit = cache.get(base);
  if (hit && now - hit.at < TTL_MS) return hit.rates;
  const r = await axios.get(`https://open.er-api.com/v6/latest/${encodeURIComponent(base)}`, { timeout: 8000 });
  if (r.data && r.data.result === "success" && r.data.rates) {
    cache.set(base, { at: now, rates: r.data.rates, updated: r.data.time_last_update_utc });
    return r.data.rates;
  }
  throw new Error("rate lookup failed");
}

// GET /api/currency/convert?from=USD&to=INR&amount=100
router.get("/convert", async (req, res) => {
  const from = String(req.query.from || "USD").toUpperCase();
  const to = String(req.query.to || "INR").toUpperCase();
  const amount = Number(req.query.amount);
  const amt = Number.isFinite(amount) ? amount : 1;
  try {
    const rates = await getRates(from);
    const rate = rates[to];
    if (!rate) return res.status(400).json({ error: `No exchange rate for ${from} → ${to}` });
    res.json({
      from,
      to,
      rate,
      amount: amt,
      result: Math.round(amt * rate * 100) / 100,
      updated: cache.get(from)?.updated || null,
    });
  } catch (e) {
    res.status(502).json({ error: "Currency service unavailable, please try again." });
  }
});

// GET /api/currency/rates?base=INR — full rate table for a base currency.
router.get("/rates", async (req, res) => {
  const base = String(req.query.base || "USD").toUpperCase();
  try {
    const rates = await getRates(base);
    res.json({ base, rates, updated: cache.get(base)?.updated || null });
  } catch (e) {
    res.status(502).json({ error: "Currency service unavailable, please try again." });
  }
});

// GET /api/currency/list — supported currencies
router.get("/list", (req, res) => {
  res.json({
    currencies: [
      { code: "INR", name: "Indian Rupee", symbol: "₹" },
      { code: "USD", name: "US Dollar", symbol: "$" },
      { code: "EUR", name: "Euro", symbol: "€" },
      { code: "GBP", name: "British Pound", symbol: "£" },
      { code: "CAD", name: "Canadian Dollar", symbol: "C$" },
      { code: "AUD", name: "Australian Dollar", symbol: "A$" },
      { code: "JPY", name: "Japanese Yen", symbol: "¥" },
      { code: "SGD", name: "Singapore Dollar", symbol: "S$" },
      { code: "AED", name: "UAE Dirham", symbol: "AED" },
    ],
  });
});

module.exports = router;
