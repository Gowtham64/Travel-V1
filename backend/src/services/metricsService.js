const os = require("os");
const https = require("https");
const http = require("http");

// Telemetry counters
const metrics = {
  startTime: Date.now(),
  totalRequests: 0,
  activeRequests: 0,
  statusCodes: { '2xx': 0, '3xx': 0, '4xx': 0, '5xx': 0 },
  latencies: [], // Rolling window of last 100 requests
  endpointHits: {},
};

// Cap the endpoint-hit map so an attacker spraying random URLs (/aaa, /bbb, …)
// can't grow the heap without bound.
const MAX_TRACKED_ENDPOINTS = 200;

function metricsMiddleware(req, res, next) {
  metrics.totalRequests++;
  metrics.activeRequests++;
  const startTime = Date.now();

  res.on("finish", () => {
    metrics.activeRequests--;
    const duration = Date.now() - startTime;

    // Record hits by MATCHED route only (after routing has run), so unmatched
    // 404 paths never create new keys. Fall back to the base URL, but stop
    // adding new keys once the map is full.
    const key = req.route ? `${req.baseUrl || ""}${req.route.path}` : req.path;
    if (key !== undefined) {
      if (metrics.endpointHits[key] !== undefined || Object.keys(metrics.endpointHits).length < MAX_TRACKED_ENDPOINTS) {
        metrics.endpointHits[key] = (metrics.endpointHits[key] || 0) + 1;
      }
    }
    
    // Store latency (keep last 100)
    metrics.latencies.push(duration);
    if (metrics.latencies.length > 100) {
      metrics.latencies.shift();
    }

    // Categorize status code
    const codeGroup = `${Math.floor(res.statusCode / 100)}xx`;
    if (metrics.statusCodes[codeGroup] !== undefined) {
      metrics.statusCodes[codeGroup]++;
    }
  });

  next();
}

function pingEndpoint(url) {
  const start = Date.now();
  return new Promise((resolve) => {
    // Guard so timeout+error (destroy() triggers both) can't settle twice.
    let settled = false;
    const done = (result) => {
      if (settled) return;
      settled = true;
      resolve(result);
    };
    const client = url.startsWith("https") ? https : http;
    const req = client.get(url, { headers: { "User-Agent": "Voyplan-StatusDashboard/1.0" } }, (res) => {
      // We only care about status + latency — drain and discard the body so we
      // don't buffer (potentially large) upstream responses in memory.
      res.resume();
      res.on("end", () => {
        done({
          url,
          status: res.statusCode,
          latencyMs: Date.now() - start,
          ok: res.statusCode >= 200 && res.statusCode < 400
        });
      });
    });
    req.on("error", (err) => {
      done({ url, status: "ERROR", error: err.message, latencyMs: Date.now() - start, ok: false });
    });
    req.setTimeout(4000, () => {
      req.destroy();
      done({ url, status: "TIMEOUT", latencyMs: Date.now() - start, ok: false });
    });
  });
}

async function getSystemTelemetry() {
  const mem = process.memoryUsage();
  const latencies = metrics.latencies;
  const avgLatency = latencies.length > 0 ? (latencies.reduce((a, b) => a + b, 0) / latencies.length).toFixed(1) : 0;
  
  const sortedLatencies = [...latencies].sort((a, b) => a - b);
  const p95 = sortedLatencies.length > 0 ? sortedLatencies[Math.floor(sortedLatencies.length * 0.95)] || sortedLatencies[sortedLatencies.length - 1] : 0;

  const totalMem = os.totalmem();
  const freeMem = os.freemem();
  const usedMem = totalMem - freeMem;

  // External dependency health checks
  const externalDependencies = await Promise.all([
    pingEndpoint("https://nominatim.openstreetmap.org/search?q=Paris&format=json").then(r => ({ name: "Nominatim Geocoding API", ...r })),
    pingEndpoint("https://overpass-api.de/api/interpreter?data=[out:json];node(around:1000,48.8566,2.3522)[amenity=fuel];out%205;").then(r => ({ name: "Overpass POI Search API", ...r })),
    pingEndpoint("https://dtemayjpttktntooxraa.supabase.co/rest/v1/").then(r => ({ name: "Supabase Database REST API", ...r, ok: r.status === 401 || r.ok })),
    pingEndpoint("https://api.openrouteservice.org/v2/health").then(r => ({ name: "OpenRouteService API", ...r, ok: r.status === 200 || r.status === 404 }))
  ]);

  return {
    timestamp: new Date().toISOString(),
    serverUptimeSeconds: Math.floor((Date.now() - metrics.startTime) / 1000),
    system: {
      platform: os.platform(),
      arch: os.arch(),
      nodeVersion: process.version,
      cpuCores: os.cpus().length,
      loadAvg: os.loadavg(),
      totalMemoryMB: Math.round(totalMem / (1024 * 1024)),
      freeMemoryMB: Math.round(freeMem / (1024 * 1024)),
      usedMemoryMB: Math.round(usedMem / (1024 * 1024)),
      memoryUsagePercent: ((usedMem / totalMem) * 100).toFixed(1)
    },
    process: {
      pid: process.pid,
      rssMB: (mem.rss / (1024 * 1024)).toFixed(2),
      heapTotalMB: (mem.heapTotal / (1024 * 1024)).toFixed(2),
      heapUsedMB: (mem.heapUsed / (1024 * 1024)).toFixed(2),
      externalMB: (mem.external / (1024 * 1024)).toFixed(2)
    },
    telemetry: {
      totalRequests: metrics.totalRequests,
      activeRequests: metrics.activeRequests,
      statusCodes: metrics.statusCodes,
      avgLatencyMs: Number(avgLatency),
      p95LatencyMs: p95,
      endpointHits: metrics.endpointHits
    },
    dependencies: externalDependencies
  };
}

module.exports = {
  metricsMiddleware,
  getSystemTelemetry
};
