import { Hono } from 'hono';
import type { Env, AppVariables } from '../types/env';
import { getRates, refresh, isStale } from '../services/priceService';

const prices = new Hono<{ Bindings: Env; Variables: AppVariables }>();

// GET /api/prices
prices.get('/', (c) => {
  c.header('Cache-Control', 'public, max-age=300, stale-while-revalidate=600');
  const rates = getRates();
  return c.json({ ...rates, stale: isStale() });
});

// POST /api/prices/refresh
prices.post('/refresh', async (c) => {
  const adminToken = c.env.PRICE_ADMIN_TOKEN;
  if (adminToken && c.req.header('x-admin-token') !== adminToken) {
    return c.json({ error: 'unauthorized' }, 401);
  }
  try {
    const refreshedRates = await refresh();
    return c.json({ refreshed: true, ...refreshedRates });
  } catch (err: any) {
    return c.json({ error: 'refresh failed', detail: err?.message }, 500);
  }
});

export default prices;
