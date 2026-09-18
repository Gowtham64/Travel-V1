import { Hono } from 'hono';
import type { Env, AppVariables } from '../types/env';
import { geocodeAddress, suggestPlaces } from '../services/geocodeService';

const geocode = new Hono<{ Bindings: Env; Variables: AppVariables }>();

// GET /api/geocode/suggest
geocode.get('/suggest', async (c) => {
  const query = c.req.query('q');
  if (!query || typeof query !== 'string' || query.trim().length < 2) {
    return c.json({ suggestions: [] });
  }

  try {
    const suggestions = await suggestPlaces(c.env, query.trim(), 6);
    c.header('Cache-Control', 'public, max-age=86400, stale-while-revalidate=604800');
    return c.json({ suggestions });
  } catch (err: any) {
    console.error('Autocomplete failed:', err?.message || err);
    return c.json({ suggestions: [] });
  }
});

// GET /api/geocode
geocode.get('/', async (c) => {
  const query = c.req.query('q');
  if (!query || typeof query !== 'string' || query.trim().length === 0) {
    return c.json({ error: 'query param ?q= is required' }, 400);
  }

  try {
    const result = await geocodeAddress(c.env, query.trim());
    if (!result) {
      return c.json({ error: 'No location found for that query' }, 404);
    }
    c.header('Cache-Control', 'public, max-age=86400, stale-while-revalidate=604800');
    return c.json(result);
  } catch (err: any) {
    console.error('Geocoding failed:', err?.message || err);
    return c.json({ error: 'Geocoding failed', detail: err?.message }, 502);
  }
});

export default geocode;
