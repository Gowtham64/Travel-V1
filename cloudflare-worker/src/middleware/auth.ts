import type { MiddlewareHandler } from 'hono';
import type { Env, AppVariables } from '../types/env';
import { getSupabaseClient } from '../services/supabase';

export const requireAuth: MiddlewareHandler<{ Bindings: Env; Variables: AppVariables }> = async (c, next) => {
  // Authenticated responses must never be cached by edge or intermediaries
  c.header('Cache-Control', 'private, no-store');

  const authHeader = c.req.header('authorization');
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return c.json({ error: 'Missing or invalid Authorization header' }, 401);
  }

  const token = authHeader.substring(7).trim();
  if (!token) {
    return c.json({ error: 'Missing or invalid Authorization header' }, 401);
  }

  const client = getSupabaseClient(c.env, token);
  if (!client) {
    return c.json({ error: 'Supabase not configured' }, 503);
  }

  try {
    const { data: { user }, error } = await client.auth.getUser(token);
    if (error || !user) {
      return c.json({ error: 'Invalid token' }, 401);
    }

    c.set('user', user);
    c.set('supabase', client);
    await next();
  } catch (err: any) {
    return c.json({ error: 'Authentication failed', message: err?.message }, 401);
  }
};
