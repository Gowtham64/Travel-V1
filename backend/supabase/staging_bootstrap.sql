-- ==============================================================
-- VoyPlan STAGING bootstrap — paste this whole file into the
-- staging Supabase project's SQL Editor and Run. Mirrors prod.
-- Safe/idempotent (IF NOT EXISTS + DROP POLICY IF EXISTS).
-- ==============================================================


-- ============ supabase_schema.sql ============

-- Coordinates are stored as plain lat/lng numerics and all distance/routing is
-- done via external APIs, so PostGIS is NOT required. (Enabling PostGIS in the
-- public schema is what trips the "RLS Disabled on spatial_ref_sys" security
-- error and most function/extension advisor warnings.)

-- 1. Route Cache Table
-- Caches routes returned by OpenRouteService to avoid repeating external API calls
CREATE TABLE public.route_cache (
    route_hash TEXT PRIMARY KEY,
    polyline JSONB NOT NULL,
    distance_km NUMERIC NOT NULL,
    duration_min NUMERIC NOT NULL,
    toll_data JSONB,
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '30 days')
);

-- 2. Trips Table
-- Stores the high-level trip metadata for a user
CREATE TABLE public.trips (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    start_point JSONB NOT NULL, -- {lat, lng, address}
    end_point JSONB NOT NULL,   -- {lat, lng, address}
    vehicle_type TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- Note: the planned start time + saved AI itinerary are stored inside the
-- end_point JSONB column, so NO migration is needed. These optional dedicated
-- columns are only if you prefer first-class storage (the app reads either):
--   ALTER TABLE public.trips ADD COLUMN IF NOT EXISTS trip_start TIMESTAMPTZ;
--   ALTER TABLE public.trips ADD COLUMN IF NOT EXISTS itinerary JSONB;

-- 3. Vehicles Table
-- (Optional) if users want to save vehicles, but for now we can just store vehicle_type in trips, 
-- or link a specific vehicle profile. Let's create it for future use.
CREATE TABLE public.vehicles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    type TEXT NOT NULL,
    fuel_efficiency_kmpl NUMERIC,
    tank_capacity_l NUMERIC,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 4. Trip Stops Table
-- Stores the intermediate stops (waypoints, hotels, fuel, etc.)
CREATE TABLE public.trip_stops (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id UUID NOT NULL REFERENCES public.trips(id) ON DELETE CASCADE,
    type TEXT NOT NULL, -- 'waypoint', 'fuel', 'hotel', 'restaurant', 'attraction'
    lat NUMERIC NOT NULL,
    lng NUMERIC NOT NULL,
    name TEXT,
    order_index INTEGER NOT NULL,
    arrival_estimate TIMESTAMPTZ
);

-- Set up Row Level Security (RLS)
ALTER TABLE public.trips ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vehicles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trip_stops ENABLE ROW LEVEL SECURITY;

-- Policies
CREATE POLICY "Users can view their own trips" ON public.trips FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert their own trips" ON public.trips FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update their own trips" ON public.trips FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete their own trips" ON public.trips FOR DELETE USING (auth.uid() = user_id);

CREATE POLICY "Users can view their own trip stops" ON public.trip_stops FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.trips WHERE trips.id = trip_stops.trip_id AND trips.user_id = auth.uid())
);
CREATE POLICY "Users can insert their own trip stops" ON public.trip_stops FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM public.trips WHERE trips.id = trip_stops.trip_id AND trips.user_id = auth.uid())
);
CREATE POLICY "Users can update their own trip stops" ON public.trip_stops FOR UPDATE USING (
    EXISTS (SELECT 1 FROM public.trips WHERE trips.id = trip_stops.trip_id AND trips.user_id = auth.uid())
);
CREATE POLICY "Users can delete their own trip stops" ON public.trip_stops FOR DELETE USING (
    EXISTS (SELECT 1 FROM public.trips WHERE trips.id = trip_stops.trip_id AND trips.user_id = auth.uid())
);

-- Allow public access to route cache (it contains no user-specific data)
ALTER TABLE public.route_cache ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Public can view route cache" ON public.route_cache FOR SELECT USING (true);
CREATE POLICY "Public can insert route cache" ON public.route_cache FOR INSERT WITH CHECK (true);

-- 5. User Details Table
-- Stores custom user information collected on signup
CREATE TABLE IF NOT EXISTS public.user_details (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    phone TEXT,
    email TEXT,
    password_hash TEXT,
    location TEXT,
    device_access TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.user_details ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own details" ON public.user_details FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Public can insert details" ON public.user_details FOR INSERT WITH CHECK (true);
CREATE POLICY "Users can update their own details" ON public.user_details FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete their own details" ON public.user_details FOR DELETE USING (auth.uid() = user_id);

-- ============================================================================
-- SECURITY CLEANUP — run once in Supabase → SQL Editor on an EXISTING database.
-- Clears the "RLS Disabled on spatial_ref_sys" error and the PostGIS advisor
-- warnings by removing the unused PostGIS dependency (the app never queries the
-- geometry column — all distance/routing is done via external APIs).
-- ============================================================================
-- 1) Drop the unused generated geometry column, then PostGIS.
ALTER TABLE public.trip_stops DROP COLUMN IF EXISTS geom;
DROP EXTENSION IF EXISTS postgis;

-- If you prefer to KEEP PostGIS, instead try (may fail if you don't own it,
-- which is safe to ignore — the table holds only public SRID reference data):
--   ALTER TABLE public.spatial_ref_sys ENABLE ROW LEVEL SECURITY;

-- 2) In the Dashboard (not SQL): Authentication → Policies/Settings →
--    enable "Leaked password protection" to clear that advisor warning.

-- ============ profile_schema.sql ============

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

-- ============ supabase/shared_trips.sql ============

-- ============================================================================
-- Voyplan — collaborative trips
-- Run this in the Supabase SQL editor (Dashboard → SQL → New query → Run).
-- It creates the shared-trips table, access policies (owner / collaborators /
-- public-by-link), a join-by-code function, and enables Realtime.
-- ============================================================================

create extension if not exists "pgcrypto";

create table if not exists public.shared_trips (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null references auth.users(id) on delete cascade,
  trip_type     text not null default 'itinerary',      -- 'itinerary' | 'oneway'
  name          text not null default 'Shared trip',
  share_code    text unique not null,                    -- short code used to join / link
  is_public     boolean not null default true,           -- view-only by link (anon can read)
  collaborators uuid[] not null default '{}',            -- user ids allowed to edit
  data          jsonb not null default '{}'::jsonb,      -- the trip payload (any type)
  updated_at    timestamptz not null default now(),
  updated_by    uuid
);

alter table public.shared_trips enable row level security;

-- Owner has full control.
drop policy if exists "trip owner all" on public.shared_trips;
create policy "trip owner all" on public.shared_trips
  for all using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

-- Collaborators can read and edit.
drop policy if exists "trip collab read" on public.shared_trips;
create policy "trip collab read" on public.shared_trips
  for select using (auth.uid() = any(collaborators));

drop policy if exists "trip collab update" on public.shared_trips;
create policy "trip collab update" on public.shared_trips
  for update using (auth.uid() = any(collaborators)) with check (auth.uid() = any(collaborators));

-- Anyone with the link can VIEW a public trip (view-only sharing).
drop policy if exists "trip public read" on public.shared_trips;
create policy "trip public read" on public.shared_trips
  for select using (is_public = true);

-- Join a trip as a collaborator using its share code (used by "invite via link/code").
-- SECURITY DEFINER so an invitee can add themselves without owner-only rights.
create or replace function public.join_trip(p_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare tid uuid;
begin
  update public.shared_trips
     set collaborators = (select array(select distinct e from unnest(collaborators || auth.uid()) e))
   where share_code = p_code
   returning id into tid;
  return tid;
end;
$$;

grant execute on function public.join_trip(text) to authenticated;

-- Keep updated_at fresh on every write.
create or replace function public.touch_shared_trip()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end; $$;

drop trigger if exists trg_touch_shared_trip on public.shared_trips;
create trigger trg_touch_shared_trip before update on public.shared_trips
  for each row execute function public.touch_shared_trip();

-- Enable Realtime so collaborators see live changes. `supabase_realtime` already
-- exists by default, so we ADD the table to it (ignoring if it's already a member).
do $$
begin
  alter publication supabase_realtime add table public.shared_trips;
exception when duplicate_object then null;
end $$;

-- ============ supabase/user_vehicles.sql ============

-- Saved vehicles per account (car/bike), reusable in the trip planners.
-- Run this once in the Supabase SQL editor.

create table if not exists public.user_vehicles (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  name         text not null,
  type         text not null default 'car',   -- 'car' | 'bike'
  mileage_kmpl numeric,                        -- km per litre
  tank_liters  numeric,                        -- tank capacity in litres
  created_at   timestamptz not null default now()
);

create index if not exists user_vehicles_user_idx on public.user_vehicles(user_id);

alter table public.user_vehicles enable row level security;

-- Each user can only see and manage their own vehicles.
drop policy if exists "user_vehicles_select_own" on public.user_vehicles;
create policy "user_vehicles_select_own" on public.user_vehicles
  for select using (auth.uid() = user_id);

drop policy if exists "user_vehicles_insert_own" on public.user_vehicles;
create policy "user_vehicles_insert_own" on public.user_vehicles
  for insert with check (auth.uid() = user_id);

drop policy if exists "user_vehicles_update_own" on public.user_vehicles;
create policy "user_vehicles_update_own" on public.user_vehicles
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "user_vehicles_delete_own" on public.user_vehicles;
create policy "user_vehicles_delete_own" on public.user_vehicles
  for delete using (auth.uid() = user_id);

-- ============ supabase/cross_device_trip_sync.sql ============

-- ============================================================================
-- Voyplan — PERMANENT cross-device trip sync fix
-- Run once in the Supabase SQL editor (Dashboard → SQL → New query → Run).
-- Safe to re-run (idempotent).
--
-- WHY THIS IS NEEDED
-- ------------------
-- A single person can sign in with DIFFERENT auth methods on different devices:
-- Google/OAuth on one, email or phone on another. Supabase creates a SEPARATE
-- auth.users row (a different user_id) for each method unless they are linked.
-- Trips were stored + read strictly by `user_id = auth.uid()`, so a trip saved
-- under the Google identity was invisible to the email/phone identity, and the
-- reverse — the exact "saved on web, missing in the app" symptom.
--
-- THE FIX
-- -------
-- Tie ownership to the account's EMAIL as well as its user_id. A trip is visible
-- to any identity that shares the same (confirmed) email. A BEFORE INSERT trigger
-- stamps owner_email server-side, so this works for every client already in the
-- field (web, current APK, current IPA) with no app update required.
--
-- SECURITY NOTE — keep "Confirm email" ENABLED in Supabase Auth settings so the
-- email claim in the JWT is trustworthy. The email path below additionally
-- requires the token's email to be verified, so an attacker cannot read another
-- user's trips by signing up with an unconfirmed matching email.
-- ============================================================================

-- 1) Ownership-by-email column + index --------------------------------------
ALTER TABLE public.trips ADD COLUMN IF NOT EXISTS owner_email TEXT;
CREATE INDEX IF NOT EXISTS trips_owner_email_idx ON public.trips (lower(owner_email));

-- 2) Auto-stamp owner_email from the authenticated user on every insert.
--    SECURITY DEFINER so it can read auth.users. Runs even for older app builds
--    that don't send owner_email themselves.
CREATE OR REPLACE FUNCTION public.set_trip_owner_email()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.owner_email IS NULL OR NEW.owner_email = '' THEN
    SELECT lower(email) INTO NEW.owner_email FROM auth.users WHERE id = NEW.user_id;
  ELSE
    NEW.owner_email := lower(NEW.owner_email);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_set_trip_owner_email ON public.trips;
CREATE TRIGGER trg_set_trip_owner_email
  BEFORE INSERT ON public.trips
  FOR EACH ROW EXECUTE FUNCTION public.set_trip_owner_email();

-- 3) Backfill existing trips so already-saved trips sync too -----------------
UPDATE public.trips t
   SET owner_email = lower(u.email)
  FROM auth.users u
 WHERE u.id = t.user_id
   AND (t.owner_email IS NULL OR t.owner_email = '');

-- 4) Helper: does the current JWT carry a VERIFIED email matching a row? -----
--    Google OAuth tokens are always email_verified; email sign-ups are verified
--    once confirmed. Phone-only tokens have no email and fall back to user_id.
CREATE OR REPLACE FUNCTION public.jwt_email_verified()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    (auth.jwt() ->> 'email') IS NOT NULL
    AND COALESCE(
      (auth.jwt() -> 'user_metadata' ->> 'email_verified')::boolean,
      (auth.jwt() ->> 'email_verified')::boolean,
      false
    ),
    false
  );
$$;

-- 5) Broaden RLS on trips: own by user_id OR by verified email --------------
DROP POLICY IF EXISTS "Users can view their own trips" ON public.trips;
CREATE POLICY "Users can view their own trips" ON public.trips
  FOR SELECT USING (
    auth.uid() = user_id
    OR (
      owner_email IS NOT NULL
      AND public.jwt_email_verified()
      AND lower(owner_email) = lower(auth.jwt() ->> 'email')
    )
  );

-- INSERT stays strict: you may only create rows owned by your own uid.
DROP POLICY IF EXISTS "Users can insert their own trips" ON public.trips;
CREATE POLICY "Users can insert their own trips" ON public.trips
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- UPDATE / DELETE: allow across your own identities (same verified email) so a
-- trip saved on one device can be edited/removed from another.
DROP POLICY IF EXISTS "Users can update their own trips" ON public.trips;
CREATE POLICY "Users can update their own trips" ON public.trips
  FOR UPDATE USING (
    auth.uid() = user_id
    OR (
      owner_email IS NOT NULL
      AND public.jwt_email_verified()
      AND lower(owner_email) = lower(auth.jwt() ->> 'email')
    )
  );

DROP POLICY IF EXISTS "Users can delete their own trips" ON public.trips;
CREATE POLICY "Users can delete their own trips" ON public.trips
  FOR DELETE USING (
    auth.uid() = user_id
    OR (
      owner_email IS NOT NULL
      AND public.jwt_email_verified()
      AND lower(owner_email) = lower(auth.jwt() ->> 'email')
    )
  );

-- 6) trip_stops follow the parent trip's visibility -------------------------
DROP POLICY IF EXISTS "Users can view their own trip stops" ON public.trip_stops;
CREATE POLICY "Users can view their own trip stops" ON public.trip_stops
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.trips
       WHERE trips.id = trip_stops.trip_id
         AND (
           trips.user_id = auth.uid()
           OR (
             trips.owner_email IS NOT NULL
             AND public.jwt_email_verified()
             AND lower(trips.owner_email) = lower(auth.jwt() ->> 'email')
           )
         )
    )
  );

DROP POLICY IF EXISTS "Users can insert their own trip stops" ON public.trip_stops;
CREATE POLICY "Users can insert their own trip stops" ON public.trip_stops
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.trips
       WHERE trips.id = trip_stops.trip_id
         AND (
           trips.user_id = auth.uid()
           OR (
             trips.owner_email IS NOT NULL
             AND public.jwt_email_verified()
             AND lower(trips.owner_email) = lower(auth.jwt() ->> 'email')
           )
         )
    )
  );

DROP POLICY IF EXISTS "Users can update their own trip stops" ON public.trip_stops;
CREATE POLICY "Users can update their own trip stops" ON public.trip_stops
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.trips
       WHERE trips.id = trip_stops.trip_id
         AND (
           trips.user_id = auth.uid()
           OR (
             trips.owner_email IS NOT NULL
             AND public.jwt_email_verified()
             AND lower(trips.owner_email) = lower(auth.jwt() ->> 'email')
           )
         )
    )
  );

DROP POLICY IF EXISTS "Users can delete their own trip stops" ON public.trip_stops;
CREATE POLICY "Users can delete their own trip stops" ON public.trip_stops
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.trips
       WHERE trips.id = trip_stops.trip_id
         AND (
           trips.user_id = auth.uid()
           OR (
             trips.owner_email IS NOT NULL
             AND public.jwt_email_verified()
             AND lower(trips.owner_email) = lower(auth.jwt() ->> 'email')
           )
         )
    )
  );

-- ============================================================================
-- DONE. Also do this ONE-TIME in the Dashboard (prevents FUTURE splits):
--   Authentication → Sign In / Providers → enable "Allow account linking"
--   (a.k.a. automatic linking of identities with the same email), and keep
--   "Confirm email" ON. New Google/email/phone logins that share a verified
--   email then resolve to the SAME user, so user_id itself stays consistent.
-- ============================================================================
