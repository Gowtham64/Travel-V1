import { Hono } from 'hono';
import type { Env, AppVariables } from '../types/env';

const currency = new Hono<{ Bindings: Env; Variables: AppVariables }>();

interface RateCacheEntry {
  at: number;
  rates: Record<string, number>;
  updated?: string;
}

const rateCache = new Map<string, RateCacheEntry>();
const TTL_MS = 60 * 60 * 1000; // 1 hour

async function getRates(base: string): Promise<Record<string, number>> {
  const now = Date.now();
  const hit = rateCache.get(base);
  if (hit && now - hit.at < TTL_MS) return hit.rates;

  const res = await fetch(`https://open.er-api.com/v6/latest/${encodeURIComponent(base)}`, {
    signal: AbortSignal.timeout(8000),
  });

  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const data: any = await res.json();

  if (data && data.result === 'success' && data.rates) {
    rateCache.set(base, { at: now, rates: data.rates, updated: data.time_last_update_utc });
    return data.rates;
  }
  throw new Error('Rate lookup failed');
}

// GET /api/currency/convert
currency.get('/convert', async (c) => {
  c.header('Cache-Control', 'public, max-age=300, stale-while-revalidate=300');
  const from = String(c.req.query('from') || 'USD').toUpperCase();
  const to = String(c.req.query('to') || 'INR').toUpperCase();
  const amount = Number(c.req.query('amount'));
  const amt = Number.isFinite(amount) ? amount : 1;

  try {
    const rates = await getRates(from);
    const rate = rates[to];
    if (!rate) return c.json({ error: `No exchange rate for ${from} → ${to}` }, 400);

    return c.json({
      from,
      to,
      rate,
      amount: amt,
      result: Math.round(amt * rate * 100) / 100,
      updated: rateCache.get(from)?.updated || null,
    });
  } catch (e) {
    return c.json({ error: 'Currency service unavailable, please try again.' }, 502);
  }
});

// GET /api/currency/rates
currency.get('/rates', async (c) => {
  c.header('Cache-Control', 'public, max-age=3600, stale-while-revalidate=3600');
  const base = String(c.req.query('base') || 'USD').toUpperCase();
  try {
    const rates = await getRates(base);
    return c.json({ base, rates, updated: rateCache.get(base)?.updated || null });
  } catch (e) {
    return c.json({ error: 'Currency service unavailable, please try again.' }, 502);
  }
});

// GET /api/currency/list
currency.get('/list', (c) => {
  c.header('Cache-Control', 'public, max-age=86400, stale-while-revalidate=86400');
  return c.json({
    currencies: [
      { code: 'INR', name: 'Indian Rupee', symbol: '₹' },
      { code: 'USD', name: 'US Dollar', symbol: '$' },
      { code: 'EUR', name: 'Euro', symbol: '€' },
      { code: 'GBP', name: 'British Pound', symbol: '£' },
      { code: 'CAD', name: 'Canadian Dollar', symbol: 'C$' },
      { code: 'AUD', name: 'Australian Dollar', symbol: 'A$' },
      { code: 'JPY', name: 'Japanese Yen', symbol: '¥' },
      { code: 'SGD', name: 'Singapore Dollar', symbol: 'S$' },
      { code: 'AED', name: 'UAE Dirham', symbol: 'AED' },
    ],
  });
});

export default currency;
