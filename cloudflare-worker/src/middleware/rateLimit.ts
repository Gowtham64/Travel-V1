import type { MiddlewareHandler } from 'hono';
import type { Env, AppVariables } from '../types/env';

interface RateLimitRecord {
  count: number;
  resetAt: number;
}

const fallbackStores = new Map<string, Map<string, RateLimitRecord>>();

function getFallbackStore(type: string): Map<string, RateLimitRecord> {
  if (!fallbackStores.has(type)) {
    fallbackStores.set(type, new Map<string, RateLimitRecord>());
  }
  return fallbackStores.get(type)!;
}

async function checkRateLimit(
  env: Env,
  ip: string,
  limit: number,
  windowMs: number,
  type: string
): Promise<{ allowed: boolean; remaining: number; reset: number }> {
  const now = Date.now();
  const kv = env.RATE_LIMIT_KV;

  if (!kv) {
    // In-memory fallback for local dev & testing when KV is not bound
    const store = getFallbackStore(type);
    let record = store.get(ip);
    if (!record || now > record.resetAt) {
      record = { count: 1, resetAt: now + windowMs };
      store.set(ip, record);
      return { allowed: true, remaining: limit - 1, reset: Math.ceil((now + windowMs) / 1000) };
    }
    if (record.count >= limit) {
      return { allowed: false, remaining: 0, reset: Math.ceil(record.resetAt / 1000) };
    }
    record.count += 1;
    if (store.size > 500) {
      for (const [k, v] of store.entries()) {
        if (now > v.resetAt) store.delete(k);
      }
    }
    return { allowed: true, remaining: limit - record.count, reset: Math.ceil(record.resetAt / 1000) };
  }

  const key = `rl:${type}:${ip}`;
  const recordStr = await kv.get(key);
  let record: RateLimitRecord | null = recordStr ? JSON.parse(recordStr) : null;

  if (!record || now > record.resetAt) {
    record = { count: 1, resetAt: now + windowMs };
    await kv.put(key, JSON.stringify(record), { expirationTtl: Math.ceil(windowMs / 1000) + 60 });
    return { allowed: true, remaining: limit - 1, reset: Math.ceil((now + windowMs) / 1000) };
  }

  if (record.count >= limit) {
    return { allowed: false, remaining: 0, reset: Math.ceil(record.resetAt / 1000) };
  }

  record.count += 1;
  await kv.put(key, JSON.stringify(record), { expirationTtl: Math.ceil((record.resetAt - now) / 1000) + 60 });
  return { allowed: true, remaining: limit - record.count, reset: Math.ceil(record.resetAt / 1000) };
}

export const generalRateLimiter: MiddlewareHandler<{ Bindings: Env; Variables: AppVariables }> = async (c, next) => {
  const ip = c.req.header('cf-connecting-ip') || c.req.header('x-forwarded-for') || '127.0.0.1';
  const { allowed, remaining, reset } = await checkRateLimit(c.env, ip, 300, 15 * 60 * 1000, 'general');

  c.header('X-RateLimit-Limit', '300');
  c.header('X-RateLimit-Remaining', remaining.toString());
  c.header('X-RateLimit-Reset', reset.toString());

  if (!allowed) {
    return c.json({ error: 'Too many requests — please slow down.' }, 429);
  }

  await next();
};

export const aiRateLimiter: MiddlewareHandler<{ Bindings: Env; Variables: AppVariables }> = async (c, next) => {
  const ip = c.req.header('cf-connecting-ip') || c.req.header('x-forwarded-for') || '127.0.0.1';
  const { allowed, remaining, reset } = await checkRateLimit(c.env, ip, 30, 60 * 1000, 'ai');

  c.header('X-RateLimit-Limit-AI', '30');
  c.header('X-RateLimit-Remaining-AI', remaining.toString());

  if (!allowed) {
    return c.json({ error: 'AI is busy — please wait a moment and try again.' }, 429);
  }

  await next();
};
