import type { MiddlewareHandler } from 'hono';
import type { Env, AppVariables } from '../types/env';

export const corsMiddleware: MiddlewareHandler<{ Bindings: Env; Variables: AppVariables }> = async (c, next) => {
  const origin = c.req.header('origin');

  const configured = (c.env.ALLOWED_ORIGINS || 'https://voyplan.in,https://www.voyplan.in')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);

  let isAllowed = false;

  if (!origin) {
    // Non-browser client (e.g. mobile app, curl)
    isAllowed = true;
  } else {
    try {
      const hostname = new URL(origin).hostname;
      if (
        configured.includes(origin) ||
        hostname.endsWith('.pages.dev') ||
        hostname === 'localhost' ||
        hostname === '127.0.0.1'
      ) {
        isAllowed = true;
      }
    } catch (_) {
      isAllowed = false;
    }
  }

  if (isAllowed && origin) {
    c.header('Access-Control-Allow-Origin', origin);
    c.header('Access-Control-Allow-Credentials', 'true');
    c.header('Access-Control-Allow-Methods', 'GET, POST, PUT, PATCH, DELETE, OPTIONS');
    c.header(
      'Access-Control-Allow-Headers',
      'Content-Type, Authorization, X-Request-ID, x-admin-token, Cache-Control, Accept, Origin'
    );
    c.header('Access-Control-Max-Age', '86400');
  }

  if (c.req.method === 'OPTIONS') {
    return c.body(null, 204);
  }

  await next();
};
