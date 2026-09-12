# VoyPlan Architecture — Database & Persistence

## 1. Primary Store
- Provider: Supabase PostgreSQL.
- Production Reference: `dtemayjpttktntooxraa`.
- Staging Reference: `voyplan-staging`.

## 2. Core Tables
- `auth.users`: User authentication profiles managed by Supabase.
- `trips`: Stores `id`, `user_id`, `destination`, `origin`, `start_date`, `end_date`, `status`, `created_at`.
- `trip_days`: Stores `id`, `trip_id`, `day_number`, `summary`.
- `trip_stops`: Stores `id`, `day_id`, `place_name`, `place_id`, `lat`, `lng`, `category`, `start_time`, `end_time`, `order_index`.
- `vehicles`: User vehicle profiles (mileage, fuel_type, tank_capacity, ev_battery_kwh).
- `saved_places`: User bookmarks and favorites.

## 3. Migration Safety Protocol
- All database modifications must be written as reversible SQL migrations in `backend/supabase/migrations/`.
- Destruction of production columns or tables is strictly forbidden without automated backup and staging verification.
