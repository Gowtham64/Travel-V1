# VoyPlan Database Architecture

## 1. Database Platform
- **Provider**: Supabase (Cloud-managed PostgreSQL 15+)
- **Production Ref**: `dtemayjpttktntooxraa`
- **Staging Ref**: `voyplan-staging`
- **Client Library**: `@supabase/supabase-js: ^2.110.2`

## 2. Core Schema & Tables

### 1. `trips`
- `id`: UUID (Primary Key)
- `user_id`: UUID (Foreign Key to `auth.users`)
- `title`: TEXT
- `origin`: JSONB (lat, lng, name, address)
- `destination`: JSONB (lat, lng, name, address, place_id)
- `trip_type`: TEXT ('one_way' | 'around')
- `start_date`: DATE
- `duration_days`: INTEGER
- `itinerary_data`: JSONB (full day-by-day blocks, travel legs, coordinates)
- `created_at`: TIMESTAMPTZ
- `updated_at`: TIMESTAMPTZ

### 2. `profiles`
- `id`: UUID (Primary Key, references `auth.users.id`)
- `full_name`: TEXT
- `avatar_url`: TEXT
- `default_vehicle_id`: UUID
- `preferred_currency`: TEXT (default: 'INR')
- `updated_at`: TIMESTAMPTZ

### 3. `user_vehicles`
- `id`: UUID (Primary Key)
- `user_id`: UUID (references `auth.users.id`)
- `make`: TEXT
- `model`: TEXT
- `year`: INTEGER
- `vehicle_type`: TEXT ('car' | 'suv' | 'bike' | 'ev')
- `fuel_type`: TEXT ('petrol' | 'diesel' | 'electric' | 'cng')
- `tank_capacity`: NUMERIC
- `mileage`: NUMERIC (km/L or km/kWh)
- `is_default`: BOOLEAN

### 4. `shared_trips`
- `id`: UUID (Primary Key)
- `trip_id`: UUID (references `trips.id`)
- `share_token`: TEXT (Unique index)
- `permission`: TEXT ('view' | 'edit')
- `expires_at`: TIMESTAMPTZ

### 5. `cross_device_trip_sync`
- Sync queue tracking real-time client mutations across web, mobile, and vehicle displays.

## 3. Production Safety Constraints
- Row-Level Security (RLS) enabled across all user data tables.
- **Strict Rule**: AI agents must never run destructive DDL/DML (`DROP`, `TRUNCATE`, unscoped `DELETE`) on production.
- Migrations must flow: `local SQL → staging Supabase → backup verification → production migration`.
