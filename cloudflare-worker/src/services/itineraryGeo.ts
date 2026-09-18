// Block types that represent an actual geographic place we can geocode.
const PLACE_TYPES = new Set(["activity", "checkin", "checkout", "start", "return", "shopping", "freetime"]);

export function haversineKm(a: { lat: number; lng: number }, b: { lat: number; lng: number }): number {
  const r = 6371.0;
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return r * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}

/**
 * Geocode a free-text place name to { lat, lng }. Uses OpenRouteService (same
 * key as routing). `focus` biases results toward that area. Returns null on failure.
 */
export async function geocode(
  name: string,
  near?: string,
  focus?: { lat: number; lng: number } | null
): Promise<{ lat: number; lng: number } | null> {
  const key = process.env.ORS_API_KEY;
  if (!key || !name) return null;
  try {
    const url = new URL("https://api.openrouteservice.org/geocode/search");
    url.searchParams.set("api_key", key);
    url.searchParams.set("text", near ? `${name}, ${near}` : name);
    url.searchParams.set("size", "1");
    if (focus) {
      url.searchParams.set("focus.point.lat", String(focus.lat));
      url.searchParams.set("focus.point.lon", String(focus.lng));
    }
    const res = await fetch(url.toString(), {
      signal: AbortSignal.timeout(8000),
    });
    if (!res.ok) return null;
    const data: any = await res.json();
    const f = data && data.features && data.features[0];
    if (!f || !f.geometry || !Array.isArray(f.geometry.coordinates)) return null;
    const [lng, lat] = f.geometry.coordinates;
    return { lat, lng };
  } catch (_) {
    return null;
  }
}

/**
 * Best-effort ISO3 country code for a place name (e.g. "IND", "ARE"), via the
 * ORS geocoder. Returns null if it can't be resolved.
 */
export async function geocodeCountry(name: string): Promise<string | null> {
  const key = process.env.ORS_API_KEY;
  if (!key || !name) return null;
  try {
    const url = new URL("https://api.openrouteservice.org/geocode/search");
    url.searchParams.set("api_key", key);
    url.searchParams.set("text", name);
    url.searchParams.set("size", "1");
    const res = await fetch(url.toString(), {
      signal: AbortSignal.timeout(8000),
    });
    if (!res.ok) return null;
    const data: any = await res.json();
    const f = data && data.features && data.features[0];
    const p = f && f.properties;
    if (!p) return null;
    return (p.country_a || p.country || "").toString().toUpperCase() || null;
  } catch (_) {
    return null;
  }
}

/**
 * Real driving distance/time between two points via the public OSRM server.
 * Returns { km, min } or null.
 */
export async function route(
  from: { lat: number; lng: number },
  to: { lat: number; lng: number }
): Promise<{ km: number; min: number } | null> {
  try {
    const url = `https://router.project-osrm.org/route/v1/driving/${from.lng},${from.lat};${to.lng},${to.lat}?overview=false`;
    const res = await fetch(url, {
      signal: AbortSignal.timeout(8000),
    });
    if (!res.ok) return null;
    const data: any = await res.json();
    const r = data && data.routes && data.routes[0];
    if (!r) return null;
    return { km: Math.round((r.distance / 1000) * 10) / 10, min: Math.round(r.duration / 60) };
  } catch (_) {
    return null;
  }
}

/**
 * Replace the AI's guessed travelMin/distanceKm on `travel` blocks with real
 * geocoded + routed values. Best-effort. Mutates `days` in place.
 */
export async function groundItinerary(days: any[], startLocation = "", destination = ""): Promise<any[]> {
  if (!Array.isArray(days) || !process.env.ORS_API_KEY) return days;
  const cache = new Map<string, any>();
  let geocodes = 0;

  const destCenter = destination ? await geocode(destination, "") : null;

  async function coordFor(name: string, { allowFar = false }: { allowFar?: boolean } = {}) {
    if (!name) return null;
    const kkey = name.toLowerCase().trim();
    if (cache.has(kkey)) return cache.get(kkey);
    if (geocodes >= 40) return null; // stay well under ORS free-tier limits
    geocodes += 1;
    let c = await geocode(name, destination || "", destCenter);
    if (c && destCenter && !allowFar && haversineKm(destCenter, c) > 250) c = null;
    cache.set(kkey, c);
    return c;
  }

  for (const day of days) {
    const blocks = Array.isArray(day.blocks) ? day.blocks : [];

    for (const b of blocks) {
      if (PLACE_TYPES.has(b.type)) {
        b._coord = await coordFor(b.place || b.title);
      }
    }

    for (let i = 0; i < blocks.length; i += 1) {
      if (blocks[i].type !== "travel" && blocks[i].type !== "return") continue;
      const mode = String(blocks[i].travelMode || "drive").toLowerCase();
      if (mode !== "drive" && mode !== "walk") continue;
      let from: any = null;
      for (let j = i - 1; j >= 0; j -= 1) {
        if (blocks[j]._coord) { from = blocks[j]._coord; break; }
      }
      if (!from) from = await coordFor(startLocation, { allowFar: true });
      let to: any = null;
      for (let j = i + 1; j < blocks.length; j += 1) {
        if (blocks[j]._coord) { to = blocks[j]._coord; break; }
      }
      if (!to && blocks[i].type === "return") {
        to = await coordFor(startLocation, { allowFar: true });
      }
      if (from && to) {
        const aiKm = Number(blocks[i].distanceKm) || 0;
        const r = await route(from, to);
        const agrees = aiKm < 1 || (r && r.km >= aiKm * 0.35 && r.km <= aiKm * 3);
        if (r && r.km > 0 && agrees) {
          blocks[i].distanceKm = r.km;
          blocks[i].travelMin = r.min;
          blocks[i].grounded = true;
          blocks[i].lat = to.lat;
          blocks[i].lng = to.lng;
        }
      }
    }

    for (const b of blocks) {
      if (b._coord) {
        b.lat = b._coord.lat;
        b.lng = b._coord.lng;
        delete b._coord;
      }
    }
  }
  return days;
}
