import { Hono } from 'hono';
import type { Env, AppVariables } from '../types/env';
import { findTreksNear, getTrekGeometry } from '../services/treksService';
import { getWikiPlaces } from '../services/wikiService';

const treks = new Hono<{ Bindings: Env; Variables: AppVariables }>();

// GET /api/treks/geometry
treks.get('/geometry', async (c) => {
  const id = c.req.query('id');
  if (!id || typeof id !== 'string') {
    return c.json({ error: 'id query param is required (e.g. way/123)' }, 400);
  }

  try {
    const geom = await getTrekGeometry(id);
    return c.json(geom);
  } catch (err: any) {
    console.error('Trek geometry failed:', err?.message || err);
    return c.json({ error: 'Failed to load trek geometry', detail: err?.message }, 502);
  }
});

// GET /api/treks
treks.get('/', async (c) => {
  const lat = parseFloat(c.req.query('lat') || '');
  const lng = parseFloat(c.req.query('lng') || '');
  const radius = c.req.query('radius') != null ? parseFloat(c.req.query('radius')!) : undefined;
  const limit = c.req.query('limit') != null ? parseInt(c.req.query('limit')!, 10) : undefined;

  if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
    return c.json({ error: 'lat and lng query params are required numbers' }, 400);
  }

  try {
    const trekList = await findTreksNear(lat, lng, radius, limit);

    let wiki: any[] = [];
    try {
      wiki = await getWikiPlaces(lat, lng, Math.round(radius || 20000), 15);
    } catch (_) {}

    const enriched = trekList.map((t) => {
      const match = wiki.find(
        (w) =>
          w.title &&
          (w.title.toLowerCase().includes(t.name.toLowerCase()) ||
            t.name.toLowerCase().includes(w.title.toLowerCase()))
      );
      return {
        ...t,
        description: match ? match.summary || null : null,
        imageUrl: match ? match.thumbnailUrl || null : null,
      };
    });

    return c.json({ count: enriched.length, treks: enriched });
  } catch (err: any) {
    console.error('Trek discovery failed:', err?.message || err);
    return c.json({ error: 'Failed to load treks', detail: err?.message }, 502);
  }
});

export default treks;
