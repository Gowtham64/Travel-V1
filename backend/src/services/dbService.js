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
function getRouteHash(start, end, waypoints, options = {}) {
  const data = JSON.stringify({ start, end, waypoints, options });
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
    
    // Convert back from DB format
    return {
      distanceKm: Number(data.distance_km),
      durationMin: Number(data.duration_min),
      coordinates: data.polyline,
      tollData: data.toll_data
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
  if (!supabase) return;
  
  try {
    await supabase.from('route_cache').upsert({
      route_hash: hash,
      polyline: routeData.coordinates,
      distance_km: routeData.distanceKm,
      duration_min: routeData.durationMin,
      toll_data: routeData.tollData || null,
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
