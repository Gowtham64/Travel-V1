import { Hono } from 'hono';
import type { Env, AppVariables } from './types/env';
import { corsMiddleware } from './middleware/cors';
import { securityHeadersMiddleware } from './middleware/security';
import { telemetryMiddleware } from './middleware/telemetry';
import { generalRateLimiter } from './middleware/rateLimit';

// Sub-routers
import healthRouter from './routes/health';
import statusRouter from './routes/status';
import tripRouter from './routes/trip';
import geocodeRouter from './routes/geocode';
import aiRouter from './routes/ai';
import accountRouter from './routes/account';
import currencyRouter from './routes/currency';
import treksRouter from './routes/treks';
import pricesRouter from './routes/prices';
import fuelRouter from './routes/fuel';
import vehiclesRouter from './routes/vehicles';

const app = new Hono<{ Bindings: Env; Variables: AppVariables }>();

// 1. Sync Worker environment bindings to process.env (for compatibility with services reading process.env)
app.use('*', async (c, next) => {
  if (c.env && typeof process !== 'undefined' && process.env) {
    Object.assign(process.env, c.env);
  }
  await next();
});

// 2. Global Security & Telemetry Middlewares
app.use('*', telemetryMiddleware);
app.use('*', corsMiddleware);
app.use('*', securityHeadersMiddleware);

// 3. Health check endpoints (exempt from rate limiting so uptime monitors never get 429'd)
app.route('/', healthRouter);

// 4. Rate Limiter on API routes
app.use('/api/*', generalRateLimiter);

// 5. Mount API Routes with strict parity to Render backend
app.route('/api/trip', tripRouter);
app.route('/api/geocode', geocodeRouter);
app.route('/api/ai', aiRouter);
app.route('/api/account', accountRouter);
app.route('/api/currency', currencyRouter);
app.route('/api/treks', treksRouter);
app.route('/api/prices', pricesRouter);
app.route('/api/fuel', fuelRouter);
app.route('/api/vehicles', vehiclesRouter);

// 6. Status & Metrics Dashboard (serves /status and /api/metrics)
app.route('/', statusRouter);

app.notFound((c) => {
  const requestId = c.get('requestId');
  return c.json({ error: 'Not found', requestId }, 404);
});

// 8. Global error handler: never leak stack traces to client, attach X-Request-ID
app.onError((err, c) => {
  const requestId = c.get('requestId') || 'unknown';
  console.error(`[WORKER ERROR] [${requestId}]`, err?.stack || err?.message || err);

  if (err instanceof SyntaxError && err.message.includes('JSON')) {
    return c.json({ error: 'Invalid JSON body', requestId }, 400);
  }

  const status = (err as any).status || 500;
  return c.json({ error: 'Internal server error', requestId }, status);
});

export default app;
