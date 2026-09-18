import type { MiddlewareHandler } from 'hono';
import type { Env, AppVariables } from '../types/env';

export const securityHeadersMiddleware: MiddlewareHandler<{ Bindings: Env; Variables: AppVariables }> = async (c, next) => {
  await next();
  c.header('X-Content-Type-Options', 'nosniff');
  c.header('X-Frame-Options', 'SAMEORIGIN');
  c.header('Referrer-Policy', 'strict-origin-when-cross-origin');
  c.header('Strict-Transport-Security', 'max-age=15552000; includeSubDomains');
  c.header('Cross-Origin-Resource-Policy', 'cross-origin');
};
