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
