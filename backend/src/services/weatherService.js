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

module.exports = { getRouteWeather, describeCode, sampleRoutePoints, WEATHER_CODES };
