import type { MiddlewareHandler } from 'hono';
import type { Env, AppVariables } from '../types/env';

export const telemetryMiddleware: MiddlewareHandler<{ Bindings: Env; Variables: AppVariables }> = async (c, next) => {
  const reqId = c.req.header('x-request-id') || crypto.randomUUID();
  c.set('requestId', reqId);
  c.header('X-Request-ID', reqId);

  const start = performance.now();
  await next();
  const duration = Math.round(performance.now() - start);

  c.header('Server-Timing', `total;dur=${duration}`);

  // Structured production log without logging sensitive tokens or request bodies
  const path = c.req.path;
  const method = c.req.method;
  const status = c.res.status;
  if (path !== '/health' && path !== '/ready') {
    console.log(JSON.stringify({
      requestId: reqId,
      timestamp: new Date().toISOString(),
      method,
      path,
      status,
      durationMs: duration,
    }));
  }
};
