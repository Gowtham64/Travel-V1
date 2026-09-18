# VoyPlan Database Architecture & Management Guide

## 1. Overview

VoyPlan uses a managed **PostgreSQL** instance hosted on **Supabase Cloud** (`https://dtemayjpttktntooxraa.supabase.co`).
- Authentication links directly to `auth.users`.
- Multi-tenancy and data isolation are enforced via **Row Level Security (RLS)** policies.
- Direct client queries use PostgREST over HTTPS; backend batch operations utilize the service role.

---

## 2. Core Schema & Tables

### `public.trips`
Primary storage for itinerary data, waypoints, fuel stops, and timeline events.
- `id` (UUID, Primary Key, default `gen_random_uuid()`)
- `user_id` (UUID, references `auth.users.id` ON DELETE CASCADE)
- `title` (TEXT, NOT NULL)
- `start_location` (JSONB / TEXT)
- `end_location` (JSONB / TEXT)
- `waypoints` (JSONB, array of intermediate stops)
- `itinerary_data` (JSONB, serialized days, fuel calculations, tolls)
- `created_at` (TIMESTAMPTZ, default `now()`)
- `updated_at` (TIMESTAMPTZ, default `now()`)

### `public.user_details`
User profile and preferences. Storing passwords here is strictly prohibited (passwords are handled exclusively by `auth.users`).
- `id` (UUID, Primary Key, default `gen_random_uuid()`)
- `user_id` (UUID, UNIQUE, references `auth.users.id` ON DELETE CASCADE)
- `name` (TEXT)
- `phone` (TEXT)
- `email` (TEXT)
- `location` (TEXT)
- `device_access` (JSONB, device metadata)
- `created_at` (TIMESTAMPTZ, default `now()`)

### `public.shared_trips`
Enables collaborative and public sharing of read-only itineraries.
- `id` (UUID, Primary Key)
- `trip_id` (UUID, references `public.trips.id` ON DELETE CASCADE)
- `share_token` (TEXT, UNIQUE, indexed)
- `access_level` (TEXT, e.g. `view`, `edit`)
- `created_at` (TIMESTAMPTZ, default `now()`)

---

## 3. Row Level Security (RLS) Policies

All tables in the `public` schema have Row Level Security enabled (`ALTER TABLE <table> ENABLE ROW LEVEL SECURITY;`).

### Trips Table Policies
```sql
-- Users can read only their own trips
CREATE POLICY "Users can view own trips"
ON public.trips FOR SELECT
USING (auth.uid() = user_id);

-- Users can insert their own trips
CREATE POLICY "Users can insert own trips"
ON public.trips FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Users can update only their own trips
CREATE POLICY "Users can update own trips"
ON public.trips FOR UPDATE
USING (auth.uid() = user_id);

-- Users can delete only their own trips
CREATE POLICY "Users can delete own trips"
ON public.trips FOR DELETE
USING (auth.uid() = user_id);
```

### User Details Policies
```sql
CREATE POLICY "Users can view own profile"
ON public.user_details FOR SELECT
USING (auth.uid() = user_id);

CREATE POLICY "Users can update own profile"
ON public.user_details FOR ALL
USING (auth.uid() = user_id);
```

---

## 4. Zero-Downtime Migration Guidelines

To maintain 100% backward compatibility during releases:
1. **Never drop or rename existing columns** in a single migration step.
2. **Add columns with default values or as nullable**:
   ```sql
   ALTER TABLE public.trips ADD COLUMN IF NOT EXISTS notes TEXT;
   ```
3. **Multi-step deprecation**:
   - Step 1: Deploy code that writes to both old and new columns.
   - Step 2: Run a backfill migration.
   - Step 3: Deploy code that reads only from the new column.
   - Step 4: Drop the deprecated column in a subsequent release.

---

## 5. Live Database Health & Readiness Probe

The backend exposes `/ready` which actively tests database responsiveness without side-effects:

```javascript
// backend/src/index.js
const { data, error } = await supabase
  .from('user_details')
  .select('count', { count: 'exact', head: true })
  .limit(1);
```
If Supabase is unreachable or credentials are invalid, `/ready` returns HTTP 503 with `{ status: "degraded", error: "Database unreachable" }`.
