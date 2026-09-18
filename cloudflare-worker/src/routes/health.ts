import { Hono } from 'hono';
import type { Env, AppVariables } from '../types/env';
import { getSupabaseClient } from '../services/supabase';

const health = new Hono<{ Bindings: Env; Variables: AppVariables }>();

health.get('/health', (c) => {
  const version = c.env.APP_VERSION || '2.5.0';
  return c.json({
    status: 'ok',
    service: 'voyplan-api',
    version,
    timestamp: new Date().toISOString(),
  });
});

health.get('/ready', async (c) => {
  const version = c.env.APP_VERSION || '2.5.0';
  const checks: Record<string, string> = {
    config: 'ok',
    database: 'unknown',
  };
  let isReady = true;

  try {
    const client = getSupabaseClient(c.env);
    if (client && !c.env.SUPABASE_URL?.includes('mock')) {
      const probePromise = client.from('route_cache').select('route_hash').limit(1);
      const timeoutPromise = new Promise<{ error: any }>((_, reject) =>
        setTimeout(() => reject(new Error('timeout')), 1200)
      );
      const result = await Promise.race([probePromise, timeoutPromise]) as any;
      if (result.error && result.error.code !== 'PGRST116') {
        checks.database = 'degraded: ' + result.error.message;
      } else {
        checks.database = 'ok';
      }
    } else {
      checks.database = client ? 'ok (mock)' : 'not_configured';
    }
  } catch (err: any) {
    checks.database = 'error: ' + (err?.message || err);
    isReady = false;
  }

  return c.json(
    {
      status: isReady ? 'ready' : 'degraded',
      version,
      checks,
    },
    isReady ? 200 : 503
  );
});

export default health;
