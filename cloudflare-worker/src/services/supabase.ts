import { createClient, SupabaseClient } from '@supabase/supabase-js';
import type { Env } from '../types/env';

export const DEFAULT_SUPABASE_URL = "https://dtemayjpttktntooxraa.supabase.co";
export const DEFAULT_SUPABASE_ANON_KEY = "sb_publishable_sGmsHOvBlUiRKXz0ajEErg_vecwGFnh";

/**
 * Creates a stateless edge Supabase client using environment bindings.
 */
export function getSupabaseClient(env?: Env, bearerToken?: string): SupabaseClient | null {
  const processEnv = (globalThis as any).process?.env || {};
  const url = env?.SUPABASE_URL || processEnv.SUPABASE_URL || DEFAULT_SUPABASE_URL;
  const key = env?.SUPABASE_ANON_KEY || processEnv.SUPABASE_ANON_KEY || DEFAULT_SUPABASE_ANON_KEY;

  if (!url || !key) return null;

  return createClient(url, key, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
    realtime: {
      transport: (globalThis as any).WebSocket || class DummyWebSocket {},
    },
    global: bearerToken
      ? { headers: { Authorization: `Bearer ${bearerToken}` } }
      : undefined,
  });
}

/**
 * Generate a SHA-256 hash for route caching using native Web Crypto API.
 */
export async function getRouteHash(
  start: { lat: number; lng: number },
  end: { lat: number; lng: number },
  waypoints: Array<{ lat: number; lng: number }> = [],
  options: { avoidMotorways?: boolean } = {}
): Promise<string> {
  const normPt = (p?: { lat?: number; lng?: number } | null) => {
    if (!p || typeof p.lat !== 'number' || typeof p.lng !== 'number') return null;
    return { lat: Number(p.lat.toFixed(6)), lng: Number(p.lng.toFixed(6)) };
  };

  const data = JSON.stringify({
    start: normPt(start),
    end: normPt(end),
    waypoints: (waypoints || []).map(normPt).filter(Boolean),
    options: { avoidMotorways: Boolean(options.avoidMotorways) },
  });

  const encoder = new TextEncoder();
  const dataBuffer = encoder.encode(data);
  const hashBuffer = await crypto.subtle.digest('SHA-256', dataBuffer);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map((b) => b.toString(16).padStart(2, '0')).join('');
}

/**
 * Fetch cached route from Supabase route_cache table.
 */
export async function getCachedRoute(supabaseOrHash: any, hashOrUndefined?: string) {
  let client: SupabaseClient | null = null;
  let hash = '';
  if (typeof supabaseOrHash === 'string') {
    hash = supabaseOrHash;
    client = getSupabaseClient();
  } else {
    client = supabaseOrHash;
    hash = hashOrUndefined || '';
  }
  if (!client || !hash) return null;

  try {
    const { data, error } = await client
      .from('route_cache')
      .select('*')
      .eq('route_hash', hash)
      .gt('expires_at', new Date().toISOString())
      .maybeSingle();

    if (error || !data) return null;

    const polyline = Array.isArray(data.polyline) ? data.polyline : [];
    const tollData = data.toll_data && typeof data.toll_data === 'object' ? data.toll_data : {};
    const distanceKm = Number(data.distance_km) || 0;
    const durationMin = Number(data.duration_min) || 0;

    return {
      origin: tollData.origin || (polyline.length > 0 ? polyline[0] : null),
      destination: tollData.destination || (polyline.length > 0 ? polyline[polyline.length - 1] : null),
      waypoints: tollData.waypoints || [],
      coordinates: polyline,
      geometry: tollData.geometry || {
        type: 'LineString',
        coordinates: polyline.map((p: any) => [p.lng, p.lat]),
      },
      distanceMeters: tollData.distanceMeters ?? Math.round(distanceKm * 1000),
      distanceKm,
      durationSeconds: tollData.durationSeconds ?? Math.round(durationMin * 60),
      durationMin,
      legs: tollData.legs || [],
      steps: tollData.steps || [],
      maneuvers: tollData.maneuvers || [],
      avoidedMotorways: Boolean(tollData.avoidedMotorways),
      tollData: tollData.rawTollData || null,
      provider: 'Supabase Cache',
    };
  } catch (err: any) {
    console.error('Error fetching cached route:', err?.message || err);
    return null;
  }
}

/**
 * Save route to Supabase route_cache table with 10 min TTL.
 */
export async function cacheRoute(supabaseOrHash: any, hashOrData: any, maybeRouteData?: any) {
  let client: SupabaseClient | null = null;
  let hash = '';
  let routeData: any = null;
  if (typeof supabaseOrHash === 'string') {
    hash = supabaseOrHash;
    routeData = hashOrData;
    client = getSupabaseClient();
  } else {
    client = supabaseOrHash;
    hash = hashOrData;
    routeData = maybeRouteData;
  }
  if (!client || !hash || !routeData) return;

  try {
    await client.from('route_cache').upsert({
      route_hash: hash,
      polyline: routeData.coordinates,
      distance_km: routeData.distanceKm,
      duration_min: routeData.durationMin,
      toll_data: {
        origin: routeData.origin,
        destination: routeData.destination,
        waypoints: routeData.waypoints,
        geometry: routeData.geometry,
        distanceMeters: routeData.distanceMeters,
        durationSeconds: routeData.durationSeconds,
        legs: routeData.legs,
        steps: routeData.steps,
        maneuvers: routeData.maneuvers,
        avoidedMotorways: routeData.avoidedMotorways,
        rawTollData: routeData.tollData,
      },
      expires_at: new Date(Date.now() + 10 * 60 * 1000).toISOString(),
    });
  } catch (err: any) {
    console.warn('Could not cache route in Supabase:', err?.message || err);
  }
}
