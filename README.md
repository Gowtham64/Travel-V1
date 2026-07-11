# Travel itinerary app

A trip-planning app: enter a start and destination, pick your vehicle, and get the route,
estimated trip days, fuel/refuel stops, toll cost, and nearby hotels/restaurants/attractions -
built entirely on free and open-source tools.

## Project layout

```
backend/   Node.js + Express API (routing, fuel calc, tolls, places) - tested, runnable now
mobile/    Flutter app (iOS + Android) - needs the Flutter SDK to run
```

## Quick start

```bash
# 1. Backend
cd backend
npm install
cp .env.example .env        # add your free ORS_API_KEY and TOLLGURU_API_KEY
npm start                   # runs on http://localhost:3000

# 2. Mobile (in a separate terminal, needs Flutter SDK installed)
cd mobile
flutter pub get
flutter run
```

Get your free keys here:
- OpenRouteService (routing): https://openrouteservice.org/dev/#/signup
- TollGuru (tolls): https://tollguru.com/dashboard

No key needed for Overpass (fuel/hotel/restaurant/attraction search) or Nominatim (geocoding) -
they're fully open public OSM-based APIs.

## What's done

- **Backend is built and tested** - 19 passing unit/integration tests covering distance math,
  fuel/refuel logic, trip-day estimation, and the `/api/trip/plan` and `/api/geocode` endpoints
  (external API calls are mocked in tests so they run offline; see `backend/README.md`)
- **Mobile app scaffold is written** - home screen (trip input form), trip screen (map +
  summary), API client, and data models. This couldn't be run inside the sandbox that
  generated it (no Flutter SDK / app store toolchains available there), so treat it as a
  strong starting point to `flutter pub get` and iterate on, not a guaranteed zero-error build.

## What's next (in priority order)

1. Run `flutter pub get` and fix any dependency version mismatches (the pubspec pins
   reasonably recent versions from memory, not a live `pub.dev` check)
2. Add a response cache in the backend (Postgres/Supabase) so repeated route/POI lookups
   don't burn through the free API quotas
3. Add a "use my current location" option and a map-tap location picker, instead of
   typed addresses only
4. Let users select/deselect which suggested stops (hotel, restaurant, attraction) to
   actually include, and recompute trip days accordingly
5. Add OpenStreetMap attribution in the app's About/Settings screen (required since
   routing and places data comes from OSM)
6. Swap the bare OSM tile server for a free-tier provider with better usage limits for
   production use (Geoapify, MapTiler, or self-hosted tiles) - the public OSM tile
   server is meant for light/dev use only

See the full architecture and API breakdown from the planning conversation for more detail
on each free service used here.
