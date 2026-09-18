import { Hono } from 'hono';
import type { Env, AppVariables } from '../types/env';
import { requireAuth } from '../middleware/auth';

const account = new Hono<{ Bindings: Env; Variables: AppVariables }>();

// All account endpoints require authentication
account.use('*', requireAuth);

const PROFILE_FIELDS = [
  'display_name',
  'avatar_url',
  'phone',
  'home_city',
  'language',
  'currency',
  'theme',
  'notif_prefs',
];

// Profile endpoints
account.get('/profile', async (c) => {
  const user = c.get('user')!;
  const supabase = c.get('supabase')!;

  try {
    const { data, error } = await supabase
      .from('user_profiles')
      .select('*')
      .eq('user_id', user.id)
      .maybeSingle();

    if (error) throw error;
    return c.json(data || { user_id: user.id, language: 'en', currency: 'INR', theme: 'dark' });
  } catch (e: any) {
    return c.json({ error: e?.message || 'Failed to fetch profile' }, 500);
  }
});

account.put('/profile', async (c) => {
  const user = c.get('user')!;
  const supabase = c.get('supabase')!;

  try {
    const body = (await c.req.json().catch(() => ({}))) as Record<string, any>;
    const row: Record<string, any> = { user_id: user.id };
    for (const f of PROFILE_FIELDS) {
      if (body[f] !== undefined) row[f] = body[f];
    }
    const { data, error } = await supabase
      .from('user_profiles')
      .upsert(row, { onConflict: 'user_id' })
      .select()
      .single();

    if (error) throw error;
    return c.json(data);
  } catch (e: any) {
    return c.json({ error: e?.message || 'Failed to update profile' }, 500);
  }
});

/**
 * Generic CRUD helper for user-scoped tables
 */
function registerCrud(
  router: Hono<{ Bindings: Env; Variables: AppVariables }>,
  prefix: string,
  table: string,
  allowedFields: string[],
  orderColumn: string = 'created_at',
  ascending: boolean = false
) {
  const pick = (body: Record<string, any>) => {
    const out: Record<string, any> = {};
    for (const f of allowedFields) {
      if (body && body[f] !== undefined) out[f] = body[f];
    }
    return out;
  };

  router.get(prefix, async (c) => {
    const user = c.get('user')!;
    const supabase = c.get('supabase')!;
    const query = c.req.query();

    try {
      let q = supabase.from(table).select('*').eq('user_id', user.id);
      if (query.trip_id && allowedFields.includes('trip_id')) {
        q = q.eq('trip_id', query.trip_id);
      }
      if (query.type && allowedFields.includes('type')) {
        q = q.eq('type', query.type);
      }
      const { data, error } = await q.order(orderColumn, { ascending });
      if (error) throw error;
      return c.json(data || []);
    } catch (e: any) {
      return c.json({ error: e?.message || 'Query failed' }, 500);
    }
  });

  router.post(prefix, async (c) => {
    const user = c.get('user')!;
    const supabase = c.get('supabase')!;

    try {
      const body = (await c.req.json().catch(() => ({}))) as Record<string, any>;
      const row = { ...pick(body), user_id: user.id };
      const { data, error } = await supabase.from(table).insert(row).select().single();
      if (error) throw error;
      return c.json(data, 201);
    } catch (e: any) {
      return c.json({ error: e?.message || 'Insert failed' }, 500);
    }
  });

  router.patch(`${prefix}/:id`, async (c) => {
    const user = c.get('user')!;
    const supabase = c.get('supabase')!;
    const id = c.req.param('id');

    try {
      const body = (await c.req.json().catch(() => ({}))) as Record<string, any>;
      const { data, error } = await supabase
        .from(table)
        .update(pick(body))
        .eq('id', id)
        .eq('user_id', user.id)
        .select()
        .single();
      if (error) throw error;
      return c.json(data);
    } catch (e: any) {
      return c.json({ error: e?.message || 'Update failed' }, 500);
    }
  });

  router.delete(`${prefix}/:id`, async (c) => {
    const user = c.get('user')!;
    const supabase = c.get('supabase')!;
    const id = c.req.param('id');

    try {
      const { error } = await supabase
        .from(table)
        .delete()
        .eq('id', id)
        .eq('user_id', user.id);
      if (error) throw error;
      return c.json({ ok: true });
    } catch (e: any) {
      return c.json({ error: e?.message || 'Delete failed' }, 500);
    }
  });
}

// Favorites: Wishlist / Saved Hotels / Saved Destinations
registerCrud(account, '/favorites', 'favorites', ['type', 'name', 'ref_id', 'lat', 'lng', 'note', 'image_url']);

// Bookings: flight | hotel | train | bus | car | activity
registerCrud(account, '/bookings', 'bookings', [
  'type',
  'title',
  'provider',
  'reference',
  'start_time',
  'end_time',
  'from_loc',
  'to_loc',
  'seat',
  'status',
  'price',
  'currency',
  'details',
]);

// Budget & Expenses
registerCrud(account, '/expenses', 'expenses', ['trip_id', 'category', 'amount', 'currency', 'note', 'spent_at'], 'spent_at');
registerCrud(account, '/budgets', 'budgets', ['trip_id', 'total', 'currency', 'breakdown']);

// Travel Tools
registerCrud(account, '/documents', 'documents', ['type', 'title', 'file_url', 'expires_at', 'note']);
registerCrud(account, '/emergency', 'emergency_contacts', ['name', 'relation', 'phone', 'category', 'is_local_service', 'blood_group', 'medical_notes']);
registerCrud(account, '/packing', 'packing_items', ['trip_id', 'category', 'name', 'qty', 'packed']);
registerCrud(account, '/vehicles', 'user_vehicles', ['name', 'type', 'mileage_kmpl', 'tank_liters']);
registerCrud(account, '/notifications', 'notifications', ['type', 'title', 'body', 'read', 'scheduled_at']);

export default account;
