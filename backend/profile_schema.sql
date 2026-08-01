-- ============================================================================
-- Voyplan — Profile / account feature tables.
-- Run once in Supabase → SQL Editor. Safe to re-run (IF NOT EXISTS + idempotent
-- policy creation). Every table is per-user and protected by Row Level Security
-- so a user can only ever read/write their own rows.
-- ============================================================================

-- 1) Profile & settings (one row per user) --------------------------------
CREATE TABLE IF NOT EXISTS public.user_profiles (
  user_id     UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name TEXT,
  avatar_url   TEXT,
  phone        TEXT,
  home_city    TEXT,
  language     TEXT DEFAULT 'en',
  currency     TEXT DEFAULT 'INR',
  theme        TEXT DEFAULT 'dark',
  notif_prefs  JSONB DEFAULT '{}'::jsonb,
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2) Favorites: wishlist / saved hotels / saved destinations --------------
CREATE TABLE IF NOT EXISTS public.favorites (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  type TEXT NOT NULL,                 -- 'wishlist' | 'hotel' | 'destination'
  name TEXT NOT NULL,
  ref_id TEXT,
  lat NUMERIC,
  lng NUMERIC,
  note TEXT,
  image_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3) Bookings: flight/hotel/train/bus/car/activity ------------------------
CREATE TABLE IF NOT EXISTS public.bookings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  type TEXT NOT NULL,                 -- 'flight' | 'hotel' | 'train' | 'bus' | 'car' | 'activity'
  title TEXT NOT NULL,
  provider TEXT,
  reference TEXT,
  start_time TIMESTAMPTZ,
  end_time TIMESTAMPTZ,
  from_loc TEXT,
  to_loc TEXT,
  seat TEXT,
  status TEXT DEFAULT 'confirmed',
  price NUMERIC,
  currency TEXT DEFAULT 'INR',
  details JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 4) Budget: expenses + budgets -------------------------------------------
CREATE TABLE IF NOT EXISTS public.expenses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  trip_id UUID REFERENCES public.trips(id) ON DELETE SET NULL,
  category TEXT NOT NULL,
  amount NUMERIC NOT NULL,
  currency TEXT DEFAULT 'INR',
  note TEXT,
  spent_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.budgets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  trip_id UUID REFERENCES public.trips(id) ON DELETE SET NULL,
  total NUMERIC NOT NULL,
  currency TEXT DEFAULT 'INR',
  breakdown JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 5) Travel Tools ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  type TEXT NOT NULL,                 -- 'passport' | 'visa' | 'insurance' | 'ticket' | ...
  title TEXT NOT NULL,
  file_url TEXT,
  expires_at TIMESTAMPTZ,
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.emergency_contacts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  relation TEXT,
  phone TEXT,
  category TEXT,                       -- 'personal' | 'police' | 'hospital' | 'ambulance' | 'embassy'
  is_local_service BOOLEAN DEFAULT false,
  blood_group TEXT,
  medical_notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.packing_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  trip_id UUID REFERENCES public.trips(id) ON DELETE CASCADE,
  category TEXT,
  name TEXT NOT NULL,
  qty INTEGER DEFAULT 1,
  packed BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 6) Notifications --------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  type TEXT,                           -- 'flight' | 'hotel' | 'weather' | 'document' | ...
  title TEXT NOT NULL,
  body TEXT,
  read BOOLEAN DEFAULT false,
  scheduled_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- Row Level Security — every table: a user only sees/edits their own rows.
-- ============================================================================
DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'user_profiles','favorites','bookings','expenses','budgets',
    'documents','emergency_contacts','packing_items','notifications'
  ] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', t);
    EXECUTE format('DROP POLICY IF EXISTS "own_select" ON public.%I;', t);
    EXECUTE format('DROP POLICY IF EXISTS "own_insert" ON public.%I;', t);
    EXECUTE format('DROP POLICY IF EXISTS "own_update" ON public.%I;', t);
    EXECUTE format('DROP POLICY IF EXISTS "own_delete" ON public.%I;', t);
    EXECUTE format('CREATE POLICY "own_select" ON public.%I FOR SELECT USING (auth.uid() = user_id);', t);
    EXECUTE format('CREATE POLICY "own_insert" ON public.%I FOR INSERT WITH CHECK (auth.uid() = user_id);', t);
    EXECUTE format('CREATE POLICY "own_update" ON public.%I FOR UPDATE USING (auth.uid() = user_id);', t);
    EXECUTE format('CREATE POLICY "own_delete" ON public.%I FOR DELETE USING (auth.uid() = user_id);', t);
  END LOOP;
END $$;

-- Helpful indexes for list queries.
CREATE INDEX IF NOT EXISTS idx_favorites_user ON public.favorites(user_id, type);
CREATE INDEX IF NOT EXISTS idx_bookings_user ON public.bookings(user_id, type);
CREATE INDEX IF NOT EXISTS idx_expenses_user ON public.expenses(user_id, trip_id);
CREATE INDEX IF NOT EXISTS idx_documents_user ON public.documents(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_user ON public.notifications(user_id, read);
CREATE INDEX IF NOT EXISTS idx_packing_user ON public.packing_items(user_id, trip_id);
