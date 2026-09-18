import type { MiddlewareHandler } from 'hono';
import type { Env, AppVariables } from '../types/env';

interface RateLimitRecord {
  count: number;
  resetAt: number;
}

const generalLimits = new Map<string, RateLimitRecord>();
const aiLimits = new Map<string, RateLimitRecord>();

function checkRateLimit(
  store: Map<string, RateLimitRecord>,
  ip: string,
  limit: number,
  windowMs: number
): { allowed: boolean; remaining: number; reset: number } {
  const now = Date.now();
  const record = store.get(ip);

  if (!record || now > record.resetAt) {
    store.set(ip, { count: 1, resetAt: now + windowMs });
    return { allowed: true, remaining: limit - 1, reset: Math.ceil((now + windowMs) / 1000) };
  }

  if (record.count >= limit) {
    return { allowed: false, remaining: 0, reset: Math.ceil(record.resetAt / 1000) };
  }

  if (store.size > 500) {
    for (const [k, v] of store.entries()) {
      if (now > v.resetAt) store.delete(k);
    }
  }

  record.count += 1;
  return { allowed: true, remaining: limit - record.count, reset: Math.ceil(record.resetAt / 1000) };
}

export const generalRateLimiter: MiddlewareHandler<{ Bindings: Env; Variables: AppVariables }> = async (c, next) => {
  const ip = c.req.header('cf-connecting-ip') || c.req.header('x-forwarded-for') || '127.0.0.1';
  const { allowed, remaining, reset } = checkRateLimit(generalLimits, ip, 300, 15 * 60 * 1000);

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
  const { allowed, remaining, reset } = checkRateLimit(aiLimits, ip, 30, 60 * 1000);

  c.header('X-RateLimit-Limit-AI', '30');
  c.header('X-RateLimit-Remaining-AI', remaining.toString());

  if (!allowed) {
    return c.json({ error: 'AI is busy — please wait a moment and try again.' }, 429);
  }

  await next();
};
