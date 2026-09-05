const axios = require("axios");
const { annotateCumulativeDistance } = require("../utils/geo");

/**
 * WMO weather interpretation codes -> human label + a simple icon key the app
 * can map to an asset/emoji. https://open-meteo.com/en/docs
 */
const WEATHER_CODES = {
  0: { label: "Clear sky", icon: "clear" },
  1: { label: "Mainly clear", icon: "clear" },
  2: { label: "Partly cloudy", icon: "partly_cloudy" },
  3: { label: "Overcast", icon: "cloudy" },
  45: { label: "Fog", icon: "fog" },
  48: { label: "Rime fog", icon: "fog" },
  51: { label: "Light drizzle", icon: "drizzle" },
  53: { label: "Drizzle", icon: "drizzle" },
  55: { label: "Heavy drizzle", icon: "drizzle" },
  56: { label: "Freezing drizzle", icon: "drizzle" },
  57: { label: "Freezing drizzle", icon: "drizzle" },
  61: { label: "Light rain", icon: "rain" },
  63: { label: "Rain", icon: "rain" },
  65: { label: "Heavy rain", icon: "rain" },
  66: { label: "Freezing rain", icon: "rain" },
  67: { label: "Freezing rain", icon: "rain" },
  71: { label: "Light snow", icon: "snow" },
  73: { label: "Snow", icon: "snow" },
  75: { label: "Heavy snow", icon: "snow" },
  77: { label: "Snow grains", icon: "snow" },
  80: { label: "Rain showers", icon: "rain" },
  81: { label: "Rain showers", icon: "rain" },
  82: { label: "Violent rain showers", icon: "rain" },
  85: { label: "Snow showers", icon: "snow" },
  86: { label: "Snow showers", icon: "snow" },
  95: { label: "Thunderstorm", icon: "thunderstorm" },
  96: { label: "Thunderstorm w/ hail", icon: "thunderstorm" },
  99: { label: "Thunderstorm w/ hail", icon: "thunderstorm" },
};

function describeCode(code) {
  return WEATHER_CODES[code] || { label: "Unknown", icon: "cloudy" };
}

/**
 * Pick a handful of evenly-spaced sample points along the route so we get a
 * weather reading near the start, a couple in the middle, and near the end.
 */
function sampleRoutePoints(routeCoordinates, maxSamples = 5) {
  const annotated = annotateCumulativeDistance(routeCoordinates);
  const totalKm = annotated[annotated.length - 1].cumulativeKm;
  const count = Math.min(maxSamples, annotated.length);
  const targets = [];
  for (let i = 0; i < count; i += 1) {
    targets.push((totalKm * i) / (count - 1 || 1));
  }

  const samples = [];
  let cursor = 0;
  for (const targetKm of targets) {
    while (cursor < annotated.length - 1 && annotated[cursor].cumulativeKm < targetKm) {
      cursor += 1;
    }
    const p = annotated[cursor];
    samples.push({
      lat: p.lat,
      lng: p.lng,
      distanceFromStartKm: Math.round(p.cumulativeKm * 10) / 10,
    });
  }
  return samples;
}

/**
 * Fetch the current weather at several points along the route using the free,
 * key-less Open-Meteo API. All sample points are requested in a single call.
 *
 * @returns {Promise<{ points: Array, hasAlerts: boolean } | null>}
 */
async function getRouteWeather(routeCoordinates) {
  if (!Array.isArray(routeCoordinates) || routeCoordinates.length < 2) {
    return null;
  }

  const samples = sampleRoutePoints(routeCoordinates, 5);
  const lats = samples.map((s) => s.lat).join(",");
  const lngs = samples.map((s) => s.lng).join(",");

  const url =
    `https://api.open-meteo.com/v1/forecast?latitude=${lats}&longitude=${lngs}` +
    `&current=temperature_2m,weather_code,wind_speed_10m,precipitation,relative_humidity_2m` +
    `&daily=precipitation_probability_max&forecast_days=1&timezone=auto`;

  const response = await axios.get(url, { timeout: 8000 });
  // Open-Meteo returns an array when multiple coordinates are requested, and a
  // single object when only one is requested. Normalise to an array.
  const raw = response.data;
  const entries = Array.isArray(raw) ? raw : [raw];

  const points = entries.map((entry, i) => {
    const current = entry.current || {};
    const daily = entry.daily || {};
    const code = current.weather_code ?? 0;
    const desc = describeCode(code);
    const rainChance = Array.isArray(daily.precipitation_probability_max)
      ? daily.precipitation_probability_max[0]
      : null;
    return {
      lat: samples[i].lat,
      lng: samples[i].lng,
      distanceFromStartKm: samples[i].distanceFromStartKm,
      tempC: current.temperature_2m ?? null,
      weatherCode: code,
      description: desc.label,
      icon: desc.icon,
      windKph: current.wind_speed_10m != null ? Math.round(current.wind_speed_10m) : null,
      humidity: current.relative_humidity_2m ?? null,
      precipitationMm: current.precipitation ?? null,
      rainChancePct: rainChance,
    };
  });

  // Flag the trip if any segment has meaningful rain/storm risk so the app can
  // surface a warning banner.
  const hasAlerts = points.some(
    (p) => ["rain", "thunderstorm", "snow"].includes(p.icon) || (p.rainChancePct ?? 0) >= 60
  );

  return { points, hasAlerts };
}

/**
 * Look at the hourly forecast at the start point over the next `hours` and
 * recommend the driest departure window. Returns null on failure.
 *
 * @returns {Promise<{ bestOffsetHours:number, bestLabel:string, driestRainPct:number,
 *   nowRainPct:number, recommendation:string, hourly:Array } | null>}
 */
async function getDepartureAdvice(start, hours = 12, departAt = null) {
  if (!start || typeof start.lat !== "number" || typeof start.lng !== "number") {
    return null;
  }

  // A planned start further out needs a longer forecast horizon.
  const forecastDays = departAt ? 4 : 2;
  const url =
    `https://api.open-meteo.com/v1/forecast?latitude=${start.lat}&longitude=${start.lng}` +
    `&hourly=precipitation_probability,weather_code,temperature_2m&forecast_days=${forecastDays}&timezone=auto`;

  const response = await axios.get(url, { timeout: 8000 });
  const h = response.data && response.data.hourly;
  if (!h || !Array.isArray(h.time)) return null;
  // Open-Meteo may omit an hourly field; default each parallel array to [] so
  // indexing below can't throw a TypeError on undefined.
  const weatherCodes = Array.isArray(h.weather_code) ? h.weather_code : [];
  const rainProbs = Array.isArray(h.precipitation_probability) ? h.precipitation_probability : [];
  const temps = Array.isArray(h.temperature_2m) ? h.temperature_2m : [];

  // Anchor the window at the planned departure (local wall-time, matching
  // Open-Meteo's timezone=auto), else at "now". Open-Meteo hourly arrays are
  // "yyyy-mm-ddThh:mm"; compare on the yyyy-mm-ddThh prefix.
  const planned = !!departAt;
  // Open-Meteo hourly times are in the location's LOCAL wall-time (timezone=auto).
  // For the "now" case we must shift the current UTC instant by the location's
  // offset, else the anchor is off by that offset (e.g. ~5.5h in India) and the
  // advice reflects hours already in the past.
  const utcOffsetSec = Number(response.data.utc_offset_seconds) || 0;
  const localNowPrefix = new Date(Date.now() + utcOffsetSec * 1000)
    .toISOString()
    .slice(0, 13);
  const anchorPrefix = planned ? String(departAt).slice(0, 13) : localNowPrefix;
  let startIdx = h.time.findIndex((t) => t.slice(0, 13) >= anchorPrefix);
  if (startIdx < 0) startIdx = 0;

  const window = [];
  for (let i = 0; i < hours && startIdx + i < h.time.length; i += 1) {
    const idx = startIdx + i;
    const code = weatherCodes[idx] ?? 0;
    window.push({
      offsetHours: i,
      time: h.time[idx],
      rainChancePct: rainProbs[idx] ?? 0,
      tempC: temps[idx] ?? null,
      icon: describeCode(code).icon,
      description: describeCode(code).label,
    });
  }
  if (window.length === 0) return null;

  const nowRainPct = window[0].rainChancePct;
  // Pick the earliest hour whose rain chance is the minimum in the window.
  let best = window[0];
  for (const w of window) {
    if (w.rainChancePct < best.rainChancePct) best = w;
  }

  function label(offset) {
    if (offset === 0) return planned ? "at your start time" : "now";
    if (offset === 1) return planned ? "1 hour later" : "in 1 hour";
    return planned ? `${offset} hours later` : `in ${offset} hours`;
  }

  let recommendation;
  if (nowRainPct < 30) {
    recommendation = planned
      ? `Looking good — only ${nowRainPct}% rain risk at your planned start.`
      : "Good time to leave — low rain risk right now.";
  } else if (best.offsetHours === 0 || best.rainChancePct >= nowRainPct - 15) {
    recommendation = planned
      ? `Rain likely (${nowRainPct}%) around your start — no clearly drier window nearby.`
      : `Rain likely (${nowRainPct}%) — no clearly drier window in the next ${hours}h.`;
  } else {
    recommendation = `Leaving ${label(best.offsetHours)} cuts rain risk from ${nowRainPct}% to ${best.rainChancePct}%.`;
  }

  return {
    bestOffsetHours: best.offsetHours,
    bestLabel: label(best.offsetHours),
    driestRainPct: best.rainChancePct,
    nowRainPct,
    recommendation,
    hourly: window,
  };
}

/**
 * Suggest rest breaks based on total driving time. Drivers should stop roughly
 * every `intervalHours`; we place a break at each interval and map it to a
 * distance along the route (assuming roughly constant average speed).
 *
 * @returns {Array<{ afterHours:number, distanceFromStartKm:number, lat:number, lng:number, label:string }>}
 */
function suggestRestStops(routeCoordinates, durationMinutes, intervalHours = 2.5, totalRouteDistanceKm = null) {
  if (!Array.isArray(routeCoordinates) || routeCoordinates.length < 2 || durationMinutes <= 0) {
    return [];
  }
  const totalHours = durationMinutes / 60;
  if (totalHours <= intervalHours) return [];

  const annotated = annotateCumulativeDistance(routeCoordinates);
  const haversineTotalKm = annotated[annotated.length - 1].cumulativeKm;
  const totalKm = (typeof totalRouteDistanceKm === "number" && totalRouteDistanceKm > 0)
    ? totalRouteDistanceKm
    : haversineTotalKm;
  const scale = haversineTotalKm > 0 ? (totalKm / haversineTotalKm) : 1.0;

  const stops = [];
  for (let t = intervalHours; t < totalHours - 0.5; t += intervalHours) {
    const fraction = t / totalHours;
    const targetKm = totalKm * fraction;
    const targetHaversineKm = targetKm / scale;
    // Find the route point nearest that cumulative distance.
    let pt = annotated[0];
    for (const p of annotated) {
      if (p.cumulativeKm >= targetHaversineKm) { pt = p; break; }
    }
    stops.push({
      afterHours: Math.round(t * 10) / 10,
      distanceFromStartKm: Math.round(targetKm * 10) / 10,
      lat: pt.lat,
      lng: pt.lng,
      label: `Suggested break after ${t % 1 === 0 ? t : t.toFixed(1)}h of driving`,
    });
  }
  return stops;
}

module.exports = {
  getRouteWeather,
  getDepartureAdvice,
  suggestRestStops,
  describeCode,
  sampleRoutePoints,
  WEATHER_CODES,
};
