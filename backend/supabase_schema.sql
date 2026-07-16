-- Enable PostGIS for spatial queries
CREATE EXTENSION IF NOT EXISTS postgis;

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
    arrival_estimate TIMESTAMPTZ,
    -- PostGIS spatial column for distance queries if needed
    geom geometry(Point, 4326) GENERATED ALWAYS AS (ST_SetSRID(ST_MakePoint(lng, lat), 4326)) STORED
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
