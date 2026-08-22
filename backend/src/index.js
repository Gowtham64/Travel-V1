// Load backend/.env by absolute path so a local run works from ANY working
// directory (dotenv otherwise only looks in process.cwd()). Harmless in prod —
// hosts like Render inject env vars directly and have no .env file.
require("dotenv").config({ path: require("path").join(__dirname, "..", ".env") });
const express = require("express");
const cors = require("cors");
const helmet = require("helmet");
const rateLimit = require("express-rate-limit");
const tripRouter = require("./routes/trip");
const geocodeRouter = require("./routes/geocode");
const aiRouter = require("./routes/ai");
const accountRouter = require("./routes/account");
const currencyRouter = require("./routes/currency");
const statusRouter = require("./routes/status");
const { metricsMiddleware } = require("./services/metricsService");

const app = express();

// Render/most PaaS terminate TLS at a proxy, so trust the first hop for correct
// client IPs (rate limiting) and HTTPS detection.
app.set("trust proxy", 1);

// --- Telemetry & APM Middleware ---
app.use(metricsMiddleware);

// --- Security headers (incl. HSTS: forces browsers onto encrypted HTTPS) ---
app.use(
  helmet({
    // Pure JSON API consumed from another origin — allow cross-origin use and
    // skip the HTML content-security-policy (there are no pages to protect).
    contentSecurityPolicy: false,
    crossOriginResourcePolicy: { policy: "cross-origin" },
    hsts: { maxAge: 15552000, includeSubDomains: true }, // 180 days
  })
);

// --- CORS restricted to the app's own origins (a browser-side firewall) ---
const allowedOrigins = (
  process.env.ALLOWED_ORIGINS ||
  "https://gowtham64.github.io,http://localhost:3000,http://localhost:8080,http://localhost:5000"
)
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);

app.use(
  cors({
    origin(origin, cb) {
      // Allow non-browser clients (mobile app, curl) which send no Origin.
      if (!origin) return cb(null, true);
      let host = "";
      try {
        host = new URL(origin).hostname;
      } catch (_) {
        return cb(null, false);
      }
      // Any GitHub Pages site or an explicitly allow-listed origin.
      if (host.endsWith(".github.io") || allowedOrigins.includes(origin)) return cb(null, true);
      return cb(null, false);
    },
  })
);

app.use(express.json({ limit: "1mb" }));

// --- Rate limiting: throttle abusive traffic (DoS / brute-force firewall) ---
app.use(
  rateLimit({
    windowMs: 15 * 60 * 1000, // 15 min
    max: 300, // per IP per window
    standardHeaders: true,
    legacyHeaders: false,
    message: { error: "Too many requests — please slow down." },
  })
);
// Stricter cap on the expensive AI endpoints.
const aiLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 min
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: "AI is busy — please wait a moment and try again." },
});

app.get("/health", (req, res) => res.json({ status: "ok" }));

app.use("/api/trip", tripRouter);
app.use("/api/geocode", geocodeRouter);
app.use("/api/ai", aiLimiter, aiRouter);
app.use("/api/account", accountRouter);
app.use("/api/currency", currencyRouter);
app.use("/", statusRouter);

// --- 404 for unmatched API routes (sanitized JSON, never an HTML stack page) ---
app.use((req, res) => {
  res.status(404).json({ error: "Not found" });
});

// --- Terminal error handler: sanitized JSON, never leaks stack traces ---
// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  // Malformed JSON bodies surface here as a SyntaxError from express.json().
  if (err && err.type === "entity.parse.failed") {
    return res.status(400).json({ error: "Invalid JSON body" });
  }
  console.error("Unhandled error:", err && err.stack ? err.stack : err);
  if (res.headersSent) return next(err);
  res.status(err.status || 500).json({ error: "Internal server error" });
});

const PORT = process.env.PORT || 3000;

// --- Process-level guards: log instead of crashing on an unexpected async error ---
process.on("unhandledRejection", (reason) => {
  console.error("Unhandled promise rejection:", reason);
});
process.on("uncaughtException", (err) => {
  console.error("Uncaught exception:", err);
});

// --- Startup config check: warn loudly about any missing keys so a misconfigured
// deploy is obvious in the logs instead of failing silently at request time. ---
function checkConfig() {
  const optional = {
    MAPBOX_TOKEN: "traffic-aware routing + geocoding (falls back to ORS/Nominatim)",
    ORS_API_KEY: "routing fallback",
    SUPABASE_URL: "auth + saved trips",
    SUPABASE_ANON_KEY: "auth + saved trips",
  };
  const missing = Object.keys(optional).filter((k) => !process.env[k]);
  if (missing.length) {
    console.warn(
      "\n⚠️  Missing environment variables (features degraded):\n" +
        missing.map((k) => `   - ${k}: ${optional[k]}`).join("\n") +
        "\n   Set them in backend/.env (local) or your host's dashboard (prod).\n"
    );
  }
}

if (require.main === module) {
  checkConfig();
  app.listen(PORT, () => {
    console.log(`Travel app backend listening on http://localhost:${PORT}`);
  });
}

module.exports = app;
