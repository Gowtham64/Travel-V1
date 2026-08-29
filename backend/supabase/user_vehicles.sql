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
