import type { Env } from '../types/env';

export interface GeocodeResult {
  lat: number;
  lng: number;
  displayName: string;
}

export interface PlaceSuggestion {
  name: string;
  lat: number;
  lng: number;
}

const GEOCODE_CACHE_TTL_MS = 24 * 60 * 60 * 1000;
const MAX_GEOCODE_CACHE = 500;
const geocodeCache = new Map<string, { value: GeocodeResult; timestamp: number }>();
const suggestCache = new Map<string, { value: PlaceSuggestion[]; timestamp: number }>();

function getCached<T>(map: Map<string, { value: T; timestamp: number }>, key: string): T | null {
  const hit = map.get(key);
  if (!hit) return null;
  if (Date.now() - hit.timestamp > GEOCODE_CACHE_TTL_MS) {
    map.delete(key);
    return null;
  }
  return hit.value;
}

function setCached<T>(map: Map<string, { value: T; timestamp: number }>, key: string, value: T) {
  if (map.size >= MAX_GEOCODE_CACHE) {
    const oldest = map.keys().next().value;
    if (oldest) map.delete(oldest);
  }
  map.set(key, { value, timestamp: Date.now() });
}

async function geocodeWithMapbox(env: Env, query: string): Promise<GeocodeResult | null> {
  const token = env.MAPBOX_TOKEN;
  if (!token) throw new Error('MAPBOX_TOKEN not configured');

  const url = `https://api.mapbox.com/geocoding/v5/mapbox.places/${encodeURIComponent(query)}.json?access_token=${encodeURIComponent(token)}&limit=1&proximity=78.9629,20.5937&language=en`;
  const res = await fetch(url, { signal: AbortSignal.timeout(8000) });
  if (!res.ok) throw new Error(`Mapbox error ${res.status}`);

  const data: any = await res.json();
  const features = data?.features;
  if (!features || features.length === 0) return null;

  const f = features[0];
  const [lng, lat] = f.center;
  return {
    lat: parseFloat(lat),
    lng: parseFloat(lng),
    displayName: f.place_name || query,
  };
}

async function geocodeWithORS(env: Env, query: string): Promise<GeocodeResult | null> {
  const orsKey = env.ORS_API_KEY;
  if (!orsKey) throw new Error('ORS_API_KEY not configured');

  const url = `https://api.openrouteservice.org/geocode/search?api_key=${encodeURIComponent(orsKey)}&text=${encodeURIComponent(query)}&size=1&focus.point.lon=78.9629&focus.point.lat=20.5937`;
  const res = await fetch(url, { signal: AbortSignal.timeout(8000) });
  if (!res.ok) throw new Error(`ORS error ${res.status}`);

  const data: any = await res.json();
  const feats = data?.features || [];
  const f = feats.find(
    (x: any) => x.geometry && Array.isArray(x.geometry.coordinates) && x.geometry.coordinates.length === 2
  );
  if (!f) return null;

  return {
    lat: parseFloat(f.geometry.coordinates[1]),
    lng: parseFloat(f.geometry.coordinates[0]),
    displayName: f.properties?.label || f.properties?.name || query,
  };
}

async function geocodeWithNominatim(query: string): Promise<GeocodeResult | null> {
  const url = `https://nominatim.openstreetmap.org/search?q=${encodeURIComponent(query)}&format=json&limit=1`;
  const res = await fetch(url, {
    headers: {
      'User-Agent': 'Voyplan/1.0 (https://voyplan.in/; contact: travel-app)',
    },
    signal: AbortSignal.timeout(8000),
  });
  if (!res.ok) return null;

  const data: any = await res.json();
  if (!Array.isArray(data) || data.length === 0) return null;

  const result = data[0];
  return {
    lat: parseFloat(result.lat),
    lng: parseFloat(result.lon),
    displayName: result.display_name,
  };
}

export async function geocodeAddress(envOrQuery: any, queryOrUndefined?: string): Promise<GeocodeResult | null> {
  let env: Env = (globalThis as any).process?.env || {};
  let query = '';
  if (typeof envOrQuery === 'string') {
    query = envOrQuery;
  } else {
    env = envOrQuery || env;
    query = queryOrUndefined || '';
  }

  const cacheKey = String(query || '').trim().toLowerCase();
  if (!cacheKey) return null;
  const cached = getCached(geocodeCache, cacheKey);
  if (cached) return cached;

  let result: GeocodeResult | null = null;
  // 1. ORS
  try {
    result = await geocodeWithORS(env, query);
  } catch (_) {}

  // 2. Mapbox
  if (!result) {
    try {
      result = await geocodeWithMapbox(env, query);
    } catch (_) {}
  }

  // 3. Nominatim
  if (!result) {
    try {
      result = await geocodeWithNominatim(query);
    } catch (_) {}
  }

  if (result) {
    setCached(geocodeCache, cacheKey, result);
  }
  return result;
}

export async function suggestPlaces(envOrQuery: any, queryOrLimit?: any, limit = 6): Promise<PlaceSuggestion[]> {
  let env: Env = (globalThis as any).process?.env || {};
  let query = '';
  let lim = limit;
  if (typeof envOrQuery === 'string') {
    query = envOrQuery;
    if (typeof queryOrLimit === 'number') lim = queryOrLimit;
  } else {
    env = envOrQuery || env;
    query = queryOrLimit || '';
  }

  const q = (query || '').trim();
  if (q.length < 2) return [];

  const cacheKey = `${q.toLowerCase()}:${lim}`;
  const cached = getCached(suggestCache, cacheKey);
  if (cached) return cached;

  // 1. ORS autocomplete
  if (env.ORS_API_KEY) {
    try {
      const url = `https://api.openrouteservice.org/geocode/autocomplete?api_key=${encodeURIComponent(env.ORS_API_KEY)}&text=${encodeURIComponent(q)}&size=${limit}&focus.point.lon=78.9629&focus.point.lat=20.5937`;
      const res = await fetch(url, { signal: AbortSignal.timeout(6000) });
      if (res.ok) {
        const data: any = await res.json();
        const feats = data?.features || [];
        const list = feats
          .filter((f: any) => f.geometry && Array.isArray(f.geometry.coordinates) && f.geometry.coordinates.length === 2)
          .map((f: any) => ({
            name: f.properties?.label || f.properties?.name || '',
            lng: parseFloat(f.geometry.coordinates[0]),
            lat: parseFloat(f.geometry.coordinates[1]),
          }))
          .filter((s: any) => s.name);
        if (list.length > 0) {
          setCached(suggestCache, cacheKey, list);
          return list;
        }
      }
    } catch (_) {}
  }

  // 2. Mapbox
  if (env.MAPBOX_TOKEN) {
    try {
      const url = `https://api.mapbox.com/geocoding/v5/mapbox.places/${encodeURIComponent(q)}.json?access_token=${encodeURIComponent(env.MAPBOX_TOKEN)}&autocomplete=true&limit=${limit}&proximity=78.9629,20.5937&language=en`;
      const res = await fetch(url, { signal: AbortSignal.timeout(6000) });
      if (res.ok) {
        const data: any = await res.json();
        const feats = data?.features || [];
        const list = feats
          .filter((f: any) => Array.isArray(f.center) && f.center.length === 2)
          .map((f: any) => ({
            name: f.place_name || '',
            lng: parseFloat(f.center[0]),
            lat: parseFloat(f.center[1]),
          }))
          .filter((s: any) => s.name);
        if (list.length > 0) {
          setCached(suggestCache, cacheKey, list);
          return list;
        }
      }
    } catch (_) {}
  }

  // 3. Nominatim
  try {
    const url = `https://nominatim.openstreetmap.org/search?q=${encodeURIComponent(q)}&format=json&limit=${limit}&addressdetails=0`;
    const res = await fetch(url, {
      headers: {
        'User-Agent': 'Voyplan/1.0 (https://voyplan.in/; contact: travel-app)',
      },
      signal: AbortSignal.timeout(6000),
    });
    if (res.ok) {
      const data: any = await res.json();
      const list = (data || [])
        .map((r: any) => ({
          name: r.display_name || '',
          lat: parseFloat(r.lat),
          lng: parseFloat(r.lon),
        }))
        .filter((s: any) => s.name && !Number.isNaN(s.lat) && !Number.isNaN(s.lng));
      if (list.length > 0) {
        setCached(suggestCache, cacheKey, list);
      }
      return list;
    }
  } catch (_) {}

  return [];
}
