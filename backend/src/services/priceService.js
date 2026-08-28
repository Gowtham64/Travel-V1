/**
 * Daily price service.
 *
 * Keeps a single cached table of the rates the budget estimator needs — fuel,
 * flight/train/bus/ferry ticket rates, tolls, food, stay, local taxi and the
 * USD→INR exchange rate — and refreshes it once a day.
 *
 * Sourcing today (no API keys required):
 *   - USD→INR is fetched live (open.er-api.com, free/no-key). International
 *     food/stay/taxi are held in USD and converted to INR at the live rate, so
 *     they track the rupee automatically.
 *   - Fuel, ticket ₹/km and toll ₹/km use maintained default rates. Each can be
 *     overridden with an env var, and each is a drop-in point for a real
 *     provider adapter later (e.g. Amadeus for fares) without touching callers.
 *
 * The process refreshes on boot and every 24h; getRates() also does a lazy
 * background refresh if the cache is older than a day (so it still updates on
 * hosts whose scheduler sleeps, like Render's free tier).
 */

const fs = require("fs");
const path = require("path");
const axios = require("axios");

const DAY_MS = 24 * 60 * 60 * 1000;
const CACHE_FILE = path.join(__dirname, "..", "data", "prices.json");

function envNum(name, fallback) {
  const v = Number(process.env[name]);
  return Number.isFinite(v) && v > 0 ? v : fallback;
}

// Seed table. INR figures are India mid-range; INTL figures are held in USD and
// converted at the live FX rate on each refresh.
function seed() {
  return {
    updatedAt: null,
    fxUpdatedAt: null,
    source: "seed",
    fx: { usdToInr: envNum("PRICE_USD_INR", 88) },
    // Domestic (India), INR
    fuel: {
      petrolPerLiter: envNum("PRICE_FUEL_PETROL", 102),
      dieselPerLiter: envNum("PRICE_FUEL_DIESEL", 90),
    },
    tollPerKm: envNum("PRICE_TOLL_PER_KM", 0.7),
    foodPerDay: envNum("PRICE_FOOD_PER_DAY", 600),
    stayPerNight: envNum("PRICE_STAY_PER_NIGHT", 1800),
    localTaxiPerKm: envNum("PRICE_TAXI_PER_KM", 18),
    // Per-person one-way ticket rates, INR: max(min, base + perKm*km)
    ticketRates: {
      flight: { perKm: envNum("PRICE_FLIGHT_PER_KM", 2.5), base: 1500, min: 2500 },
      train: { perKm: 1.2, base: 100, min: 250 },
      bus: { perKm: 1.0, base: 80, min: 150 },
      ferry: { perKm: 2.0, base: 200, min: 300 },
    },
    // International cost basis, USD — converted to INR fields below on refresh.
    intlUsd: {
      foodPerDay: envNum("PRICE_INTL_FOOD_USD", 30),
      stayPerNight: envNum("PRICE_INTL_STAY_USD", 80),
      localTaxiPerKm: envNum("PRICE_INTL_TAXI_USD", 0.55),
    },
    // Filled from intlUsd * fx on each refresh (INR).
    intl: { foodPerDay: 0, stayPerNight: 0, localTaxiPerKm: 0 },
  };
}

let prices = seed();
let refreshing = null; // in-flight refresh promise (dedupes concurrent calls)

// Recompute the INR international fields from the USD basis and current FX.
function recomputeIntl(p) {
  const fx = p.fx.usdToInr || 88;
  p.intl = {
    foodPerDay: Math.round(p.intlUsd.foodPerDay * fx),
    stayPerNight: Math.round(p.intlUsd.stayPerNight * fx),
    localTaxiPerKm: Math.round(p.intlUsd.localTaxiPerKm * fx),
  };
  return p;
}

function loadFromDisk() {
  try {
    const raw = fs.readFileSync(CACHE_FILE, "utf8");
    const parsed = JSON.parse(raw);
    if (parsed && parsed.fx && parsed.ticketRates) {
      prices = { ...seed(), ...parsed };
      recomputeIntl(prices);
    }
  } catch (_) {/* no cache yet — seed stands */}
}

function saveToDisk() {
  try {
    fs.mkdirSync(path.dirname(CACHE_FILE), { recursive: true });
    fs.writeFileSync(CACHE_FILE, JSON.stringify(prices, null, 2));
  } catch (_) {/* best-effort; ephemeral hosts are fine */}
}

// Live USD→INR from a free, no-key source. Returns a number or null.
async function fetchUsdInr() {
  try {
    const res = await axios.get("https://open.er-api.com/v6/latest/USD", { timeout: 8000 });
    const inr = res.data && res.data.rates && Number(res.data.rates.INR);
    return Number.isFinite(inr) && inr > 0 ? inr : null;
  } catch (_) {
    return null;
  }
}

/**
 * Refresh the price table from live sources. Best-effort: any source that fails
 * leaves that field at its last-known value. Always stamps updatedAt.
 */
async function refresh() {
  if (refreshing) return refreshing;
  refreshing = (async () => {
    const nowIso = new Date().toISOString();
    const inr = await fetchUsdInr();
    if (inr) {
      prices.fx.usdToInr = Math.round(inr * 100) / 100;
      prices.fxUpdatedAt = nowIso;
      prices.source = "live-fx";
    }
    // (Adapters for live fuel / flight fares / tolls plug in here when keys exist.)
    recomputeIntl(prices);
    prices.updatedAt = nowIso;
    saveToDisk();
    refreshing = null;
    return prices;
  })();
  return refreshing;
}

function isStale() {
  if (!prices.updatedAt) return true;
  return Date.now() - new Date(prices.updatedAt).getTime() > DAY_MS;
}

/**
 * Current price table for the budget layer. Non-blocking: if the cache is stale
 * it kicks off a background refresh but returns the current values immediately.
 */
function getRates() {
  if (isStale() && !refreshing) {
    refresh().catch(() => {});
  }
  return prices;
}

/** Start the daily refresh loop (call once at server boot). */
function startDailyRefresh() {
  loadFromDisk();
  refresh().catch(() => {});
  const timer = setInterval(() => refresh().catch(() => {}), DAY_MS);
  if (timer.unref) timer.unref(); // don't keep the process alive just for this
  return timer;
}

module.exports = { getRates, refresh, startDailyRefresh, isStale, CACHE_FILE };
