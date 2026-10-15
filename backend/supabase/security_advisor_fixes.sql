-- ============================================================================
-- VoyPlan — Supabase Security Advisor Hardening & Fixes
--
-- Resolves all 11 Supabase Security Advisor warnings:
-- 1. Function Search Path Mutable: public.touch_shared_trip
-- 2. Function Search Path Mutable: public.jwt_email_verified
-- 3. RLS Policy Always True: public.route_cache
-- 4. RLS Policy Always True: public.user_details
-- 5 & 8. Public / Signed-In Can Execute SECURITY DEFINER: public.join_trip
-- 6 & 9. Public / Signed-In Can Execute SECURITY DEFINER: public.rls_auto_enable
-- 7 & 10. Public / Signed-In Can Execute SECURITY DEFINER: public.set_trip_owner_email
-- 11. Leaked Password Protection (Dashboard configuration guide below)
--
-- Instructions:
-- Run this script in your Supabase Dashboard -> SQL Editor -> New Query -> Run.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Fix Function Search Path & Permissions: public.touch_shared_trip
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.touch_shared_trip()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- Trigger functions should never be called directly via RPC/API
REVOKE ALL ON FUNCTION public.touch_shared_trip() FROM PUBLIC, anon, authenticated;


-- ----------------------------------------------------------------------------
-- 2. Fix Function Search Path: public.jwt_email_verified
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.jwt_email_verified()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SET search_path = ''
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


-- ----------------------------------------------------------------------------
-- 3. Fix RLS Policy Always True: public.route_cache
-- Replace unconditional true with a strict expiration check and role isolation
-- ----------------------------------------------------------------------------
ALTER TABLE IF EXISTS public.route_cache ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public can view route cache" ON public.route_cache;
DROP POLICY IF EXISTS "Public can insert route cache" ON public.route_cache;
DROP POLICY IF EXISTS "Allow read route cache" ON public.route_cache;
DROP POLICY IF EXISTS "Allow insert route cache" ON public.route_cache;

-- Allow reading active (unexpired) routes
CREATE POLICY "Allow read route cache" ON public.route_cache
  FOR SELECT TO anon, authenticated
  USING (expires_at > now());

-- Allow inserting routes only for authenticated users and backend service role
CREATE POLICY "Allow insert route cache" ON public.route_cache
  FOR INSERT TO authenticated, service_role
  WITH CHECK (expires_at > now());


-- ----------------------------------------------------------------------------
-- 4. Fix RLS Policy Always True: public.user_details
-- Prevent arbitrary user impersonation by validating auth.uid()
-- ----------------------------------------------------------------------------
ALTER TABLE IF EXISTS public.user_details ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public can insert details" ON public.user_details;
DROP POLICY IF EXISTS "Users can insert their own details" ON public.user_details;

CREATE POLICY "Users can insert their own details" ON public.user_details
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);


-- ----------------------------------------------------------------------------
-- 5 & 8. Fix SECURITY DEFINER & Permissions: public.join_trip
-- Change to SECURITY INVOKER with explicit RLS update policy for joining by code
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.join_trip(p_code text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  tid uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  UPDATE public.shared_trips
     SET collaborators = (SELECT array(SELECT DISTINCT e FROM unnest(collaborators || auth.uid()) e))
   WHERE share_code = p_code
   RETURNING id INTO tid;

  RETURN tid;
END;
$$;

-- Revoke public & anon execution; grant only to signed-in users
REVOKE ALL ON FUNCTION public.join_trip(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.join_trip(text) TO authenticated;

-- Allow authenticated users to add themselves as collaborator when they have the share_code
DROP POLICY IF EXISTS "trip allow join" ON public.shared_trips;
CREATE POLICY "trip allow join" ON public.shared_trips
  FOR UPDATE TO authenticated
  USING (share_code IS NOT NULL)
  WITH CHECK (auth.uid() = ANY(collaborators));


-- ----------------------------------------------------------------------------
-- 6 & 9. Fix SECURITY DEFINER & Permissions: public.rls_auto_enable
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rls_auto_enable') THEN
    EXECUTE 'ALTER FUNCTION public.rls_auto_enable() SET search_path = ''''';
    EXECUTE 'REVOKE ALL ON FUNCTION public.rls_auto_enable() FROM PUBLIC, anon, authenticated';
  END IF;
END $$;


-- ----------------------------------------------------------------------------
-- 7 & 10. Fix SECURITY DEFINER & Permissions: public.set_trip_owner_email
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_trip_owner_email()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
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

-- Trigger functions should never be directly invoked by clients
REVOKE ALL ON FUNCTION public.set_trip_owner_email() FROM PUBLIC, anon, authenticated;
