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

-- Enable Realtime so collaborators see live changes.
alter publication supabase_realtime add table public.shared_trips;
