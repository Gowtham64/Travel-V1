import { haversineDistanceKm } from '../utils/geo';

const OVERPASS_MIRRORS = [
  'https://overpass-api.de/api/interpreter',
  'https://overpass.kumi.systems/api/interpreter',
  'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
];

async function queryOverpass(query: string): Promise<any> {
  const body = `data=${encodeURIComponent(query)}`;
  let lastError: any = null;

  for (const url of OVERPASS_MIRRORS) {
    try {
      const res = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body,
        signal: AbortSignal.timeout(12000),
      });
      if (res.ok) {
        return await res.json();
      }
      lastError = new Error(`Overpass HTTP ${res.status}`);
    } catch (err: any) {
      lastError = err;
    }
  }
  throw lastError || new Error('All Overpass mirrors failed');
}

const SAC_SCALE_LABELS: Record<string, string> = {
  hiking: 'Easy',
  mountain_hiking: 'Moderate',
  demanding_mountain_hiking: 'Hard',
  alpine_hiking: 'Very hard',
  demanding_alpine_hiking: 'Expert',
  difficult_alpine_hiking: 'Expert',
};

export function difficultyFromTags(tags: Record<string, any>): string | null {
  if (tags.sac_scale && SAC_SCALE_LABELS[tags.sac_scale]) return SAC_SCALE_LABELS[tags.sac_scale];
  if (tags.difficulty) {
    const d = String(tags.difficulty).toLowerCase();
    if (d.includes('easy')) return 'Easy';
    if (d.includes('moderate') || d.includes('medium')) return 'Moderate';
    if (d.includes('hard') || d.includes('difficult')) return 'Hard';
  }
  return null;
}

export function lengthKmFromTags(tags: Record<string, any>): number | null {
  const raw = tags.distance || tags.length;
  if (!raw) return null;
  const m = String(raw).match(/([\d.]+)/);
  if (!m) return null;
  const val = parseFloat(m[1]);
  if (!Number.isFinite(val) || val <= 0) return null;
  if (/m\b/i.test(String(raw)) && !/km/i.test(String(raw))) return Math.round((val / 1000) * 10) / 10;
  return Math.round(val * 10) / 10;
}

const ROAD_NOISE_RE = /\b(road|street|st|avenue|ave|lane|hostel|residential|parking|entrance|highway|flyover|bridge|dead[ -]?end)\b/i;

export function extractGeometry(el: any): Array<{ lat: number; lng: number }> {
  const pts: Array<{ lat: number; lng: number }> = [];
  if (Array.isArray(el.geometry)) {
    for (const g of el.geometry) {
      if (g && Number.isFinite(g.lat) && Number.isFinite(g.lon)) pts.push({ lat: g.lat, lng: g.lon });
    }
  } else if (Array.isArray(el.members)) {
    for (const m of el.members) {
      if (m && Array.isArray(m.geometry)) {
        for (const g of m.geometry) {
          if (g && Number.isFinite(g.lat) && Number.isFinite(g.lon)) pts.push({ lat: g.lat, lng: g.lon });
        }
      }
    }
  }
  return pts;
}

export function pathLengthKm(path: Array<{ lat: number; lng: number }>): number {
  let total = 0;
  for (let i = 1; i < path.length; i += 1) total += haversineDistanceKm(path[i - 1], path[i]);
  return total;
}

export function simplifyPath(path: Array<{ lat: number; lng: number }>, maxPoints: number): Array<{ lat: number; lng: number }> {
  if (path.length <= maxPoints) return path;
  const step = Math.ceil(path.length / maxPoints);
  const out: Array<{ lat: number; lng: number }> = [];
  for (let i = 0; i < path.length; i += step) out.push(path[i]);
  if (out[out.length - 1] !== path[path.length - 1]) out.push(path[path.length - 1]);
  return out;
}

export async function findTreksNear(lat: number, lng: number, radiusMeters = 20000, limit = 20) {
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
    throw new Error('lat and lng must be finite numbers');
  }
  const r = Math.min(Math.max(Number(radiusMeters) || 20000, 1000), 60000);

  const query =
    `[out:json][timeout:20];\n(\n` +
    `  way["highway"="path"]["name"](around:${r},${lat},${lng});\n` +
    `  way["highway"~"footway|steps|track|path"]["name"]["sac_scale"](around:${r},${lat},${lng});\n` +
    `  way["highway"~"path|track"]["name"]["trail_visibility"](around:${r},${lat},${lng});\n` +
    `);\nout center tags;`;

  const data = await queryOverpass(query);
  const elements = data.elements || [];

  const seen = new Set<string>();
  const treks: any[] = [];

  for (const el of elements) {
    const tags = el.tags || {};
    const name = tags.name;
    if (!name) continue;

    const graded = tags.sac_scale || tags.trail_visibility;
    if (!graded && ROAD_NOISE_RE.test(name)) continue;

    const nameKey = name.toLowerCase().trim();
    if (seen.has(nameKey)) continue;

    let elat = el.lat ?? (el.center && el.center.lat);
    let elng = el.lon ?? (el.center && el.center.lon);
    if (elat == null && el.bounds) {
      elat = (el.bounds.minlat + el.bounds.maxlat) / 2;
      elng = (el.bounds.minlon + el.bounds.maxlon) / 2;
    }
    if (elat == null || elng == null) continue;

    seen.add(nameKey);
    treks.push({
      id: `${el.type}/${el.id}`,
      name,
      lat: elat,
      lng: elng,
      distanceFromSearchKm: Math.round(haversineDistanceKm({ lat, lng }, { lat: elat, lng: elng }) * 10) / 10,
      lengthKm: lengthKmFromTags(tags),
      difficulty: difficultyFromTags(tags),
      type: tags.route ? `${tags.route} route` : 'trail',
      tags,
    });
  }

  treks.sort((a, b) => a.distanceFromSearchKm - b.distanceFromSearchKm);
  return treks.slice(0, Math.max(1, Math.min(Number(limit) || 20, 50)));
}

export async function getTrekGeometry(id: string) {
  const [type, rawId] = String(id).split('/');
  const numId = parseInt(rawId, 10);
  if (!['way', 'relation', 'node'].includes(type) || !Number.isFinite(numId)) {
    throw new Error(`invalid trek id "${id}" (expected way/<n>, relation/<n> or node/<n>)`);
  }
  const query = `[out:json][timeout:25];${type}(${numId});out geom;`;
  const data = await queryOverpass(query);
  const el = (data.elements || [])[0];
  if (!el) return { path: [], lengthKm: null };
  const full = extractGeometry(el);
  const path = simplifyPath(full, 300);
  const lengthKm = full.length > 1 ? Math.round(pathLengthKm(full) * 10) / 10 : null;
  return { path, lengthKm };
}
