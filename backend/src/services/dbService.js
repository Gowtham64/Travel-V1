const { createClient } = require('@supabase/supabase-js');
const crypto = require('crypto');
const WebSocket = require('ws');

const supabaseUrl = process.env.SUPABASE_URL || "https://dtemayjpttktntooxraa.supabase.co";
const supabaseKey = process.env.SUPABASE_ANON_KEY || "sb_publishable_sGmsHOvBlUiRKXz0ajEErg_vecwGFnh";

// Only initialize if we have the keys, otherwise degrade gracefully
let supabase = null;
if (supabaseUrl && supabaseKey) {
  supabase = createClient(supabaseUrl, supabaseKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
    realtime: {
      transport: WebSocket,
    }
  });
} else {
  console.warn("Supabase credentials not found in .env. Route caching and trip saving will be disabled.");
}

/**
 * Generate a hash for a route to use as a cache key.
 *
 * `options` (e.g. { avoidMotorways: true }) is part of the key so a bike route
 * that avoids expressways is never served from a car's cached route and vice versa.
 */
function getRouteHash(start, end, waypoints = [], options = {}) {
  const normPt = (p) => {
    if (!p || typeof p.lat !== 'number' || typeof p.lng !== 'number') return null;
    return { lat: Number(p.lat.toFixed(6)), lng: Number(p.lng.toFixed(6)) };
  };
  const data = JSON.stringify({
    start: normPt(start),
    end: normPt(end),
    waypoints: (waypoints || []).map(normPt).filter(Boolean),
    options: { avoidMotorways: Boolean(options.avoidMotorways) }
  });
  return crypto.createHash('sha256').update(data).digest('hex');
}

/**
 * Get a cached route from the database.
 */
async function getCachedRoute(hash) {
  if (!supabase) return null;
  
  try {
    const { data, error } = await supabase
      .from('route_cache')
      .select('*')
      .eq('route_hash', hash)
      .gt('expires_at', new Date().toISOString())
      .single();
      
    if (error || !data) return null;
    
    const polyline = Array.isArray(data.polyline) ? data.polyline : [];
    const tollData = (data.toll_data && typeof data.toll_data === 'object') ? data.toll_data : {};
    const distanceKm = Number(data.distance_km) || 0;
    const durationMin = Number(data.duration_min) || 0;

    return {
      origin: tollData.origin || (polyline.length > 0 ? polyline[0] : null),
      destination: tollData.destination || (polyline.length > 0 ? polyline[polyline.length - 1] : null),
      waypoints: tollData.waypoints || [],
      coordinates: polyline,
      geometry: tollData.geometry || {
        type: 'LineString',
        coordinates: polyline.map((p) => [p.lng, p.lat]),
      },
      distanceMeters: tollData.distanceMeters ?? Math.round(distanceKm * 1000),
      distanceKm: distanceKm,
      durationSeconds: tollData.durationSeconds ?? Math.round(durationMin * 60),
      durationMin: durationMin,
      legs: tollData.legs || [],
      steps: tollData.steps || [],
      maneuvers: tollData.maneuvers || [],
      avoidedMotorways: Boolean(tollData.avoidedMotorways),
      tollData: tollData.rawTollData || null,
    };
  } catch (err) {
    console.error("Error fetching cached route:", err.message);
    return null;
  }
}

/**
 * Save a route to the cache.
 */
async function cacheRoute(hash, routeData) {
  if (!supabase || !routeData) return;
  
  try {
    await supabase.from('route_cache').upsert({
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
        rawTollData: routeData.tollData || null,
      },
      expires_at: new Date(Date.now() + 10 * 60 * 1000).toISOString(), // Expire traffic-aware route in 10 minutes
    });
  } catch (err) {
    console.error("Error caching route:", err.message);
  }
}

module.exports = {
  supabase,
  getRouteHash,
  getCachedRoute,
  cacheRoute,
};
