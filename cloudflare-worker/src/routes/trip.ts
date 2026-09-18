import { Hono } from 'hono';
import type { Env, AppVariables } from '../types/env';
import { getRoute } from '../services/routingService';
import { calculateTripRoute } from '../services/routeCalculationService';
import { findPlacesAlongRoute } from '../services/placesService';
import { FuelRangeService } from '../services/fuelRangeService';
import { findRefuelStops, estimateTripDays } from '../services/fuelService';
import { getTollEstimate } from '../services/tollService';
import { getRouteWeather, getDepartureAdvice, suggestRestStops } from '../services/weatherService';
import { estimateBudget } from '../services/budgetService';
import { buildItinerary } from '../services/itineraryService';
import { getWikiPlaces } from '../services/wikiService';
import { getDestinationEvents } from '../services/eventsService';
import { annotateCumulativeDistance, nearestRouteDistanceKm } from '../utils/geo';
import { findPOIsAlongRoute } from '../services/orsPoiService';
import { createTripShare, getTripShare } from '../services/sharingService';
import { requireAuth } from '../middleware/auth';

const trip = new Hono<{ Bindings: Env; Variables: AppVariables }>();

// POST /api/trip/calculate-route
trip.post('/calculate-route', async (c) => {
  const body = (await c.req.json().catch(() => ({}))) as any;
  const {
    origin,
    destination,
    stops = [],
    vehicle = {},
    tripType = 'around',
    durationDays = 1,
    travellers = 1,
    routeVersion = 1,
    options = {},
  } = body;

  try {
    const result = await calculateTripRoute({
      origin,
      destination,
      stops,
      vehicle,
      tripType,
      durationDays,
      travellers,
      routeVersion,
      options,
    });
    return c.json(result);
  } catch (err: any) {
    console.error('[TRIP ROUTE CALCULATION] Error:', err?.message || err);
    return c.json({ error: err?.message || 'Route calculation failed' }, 400);
  }
});

function isValidPoint(p: any) {
  return p && typeof p.lat === 'number' && typeof p.lng === 'number';
}

const MOTORWAY_BANNED_TYPES = new Set([
  'motorcycle',
  'bike',
  'two_wheeler',
  '2w',
  'three_wheeler',
  '3w',
  'auto',
  'autorickshaw',
]);

function isMotorwayBanned(vehicleType: string) {
  return MOTORWAY_BANNED_TYPES.has(String(vehicleType || '').toLowerCase());
}

// POST /api/trip/plan
trip.post('/plan', async (c) => {
  const body = (await c.req.json().catch(() => ({}))) as any;
  const {
    start,
    end,
    waypoints = [],
    vehicle,
    dailyDrivingHours = 7,
    includePlaces = [],
    departAt = null,
    days: reqDays,
    durationDays: reqDurationDays,
  } = body;

  if (!isValidPoint(start) || !isValidPoint(end)) {
    return c.json({ error: 'start and end must be { lat, lng } objects' }, 400);
  }
  if (!Array.isArray(waypoints) || !waypoints.every(isValidPoint)) {
    return c.json({ error: 'waypoints must be an array of { lat, lng } objects' }, 400);
  }
  if (!vehicle || !vehicle.efficiencyKmPerLiter || !vehicle.tankCapacityLiters) {
    return c.json({ error: 'vehicle must include efficiencyKmPerLiter and tankCapacityLiters' }, 400);
  }
  if (
    !(vehicle.efficiencyKmPerLiter > 0) ||
    !(vehicle.tankCapacityLiters > 0) ||
    (vehicle.currentFuelLiters != null && vehicle.currentFuelLiters < 0)
  ) {
    return c.json(
      { error: 'vehicle efficiencyKmPerLiter and tankCapacityLiters must be positive numbers' },
      400
    );
  }

  try {
    const avoidMotorways = isMotorwayBanned(vehicle.type);
    let route = await getRoute(start, end, waypoints, { avoidMotorways });

    const currentFuelLiters = vehicle.currentFuelLiters ?? vehicle.tankCapacityLiters;

    let fuelStations: any[] = [];
    try {
      fuelStations = await findPlacesAlongRoute(route.coordinates, 'fuel');
    } catch (err: any) {
      console.error('Fuel-station lookup skipped:', err?.message || err);
    }

    let fuelPlan: any;
    try {
      fuelPlan = FuelRangeService.planSmartRefuelStops({
        routeCoordinates: route.coordinates,
        userStops: waypoints,
        stations: fuelStations,
        vehicle: {
          currentFuelLiters,
          tankCapacityLiters: vehicle.tankCapacityLiters,
          efficiencyKmPerLiter: vehicle.efficiencyKmPerLiter,
          fuelType: vehicle.fuelType,
        },
        options: {
          totalRouteDistanceKm: route.distanceKm,
        },
      });
    } catch (_) {
      fuelPlan = findRefuelStops(
        route.coordinates,
        currentFuelLiters,
        vehicle.tankCapacityLiters,
        vehicle.efficiencyKmPerLiter
      );
    }

    let navigationWaypoints: any[] = [];
    if (fuelPlan && Array.isArray(fuelPlan.refuelStops) && fuelPlan.refuelStops.length > 0) {
      const annotated = annotateCumulativeDistance(route.coordinates);
      const userWpItems = (waypoints || []).map((wp: any, idx: number) => {
        const proj = nearestRouteDistanceKm(annotated, wp);
        return {
          ...wp,
          type: 'waypoint',
          name: wp.name || `Stop ${idx + 1}`,
          distanceFromStartKm: proj.distanceFromStartKm,
          userIndex: idx,
        };
      });

      const fuelWpItems = fuelPlan.refuelStops.map((fs: any) => ({
        ...fs,
        type: 'fuel_stop',
        name: fs.name || 'Fuel Station',
        isFuelStop: true,
      }));

      const combined = [];
      for (let i = 0; i < userWpItems.length; i++) {
        const legFuelStops = fuelWpItems
          .filter((f: any) => f.legIndex === i)
          .sort((a: any, b: any) => a.distanceFromStartKm - b.distanceFromStartKm);
        combined.push(...legFuelStops);
        combined.push(userWpItems[i]);
      }
      const finalLegFuelStops = fuelWpItems
        .filter((f: any) => f.legIndex === userWpItems.length)
        .sort((a: any, b: any) => a.distanceFromStartKm - b.distanceFromStartKm);
      combined.push(...finalLegFuelStops);

      navigationWaypoints = combined;

      try {
        const mergedRouteWps = navigationWaypoints.map((w: any) => ({ lat: w.lat, lng: w.lng }));
        const reRoute = await getRoute(start, end, mergedRouteWps, { avoidMotorways });
        if (reRoute && reRoute.coordinates && reRoute.coordinates.length > 0) {
          route = reRoute;
        }
      } catch (_) {}
    } else {
      navigationWaypoints = (waypoints || []).map((wp: any, idx: number) => ({
        ...wp,
        type: 'waypoint',
        name: wp.name || `Stop ${idx + 1}`,
      }));
    }

    const naturalEstimatedDays = estimateTripDays(route.durationMin, dailyDrivingHours);
    const estimatedDays = Math.max(1, parseInt(reqDays || reqDurationDays || naturalEstimatedDays, 10));

    // Parallel external enrichments
    const [toll, weather, restStops, itinerary, departureAdvice, wikiPlaces, destinationEvents] =
      await Promise.all([
        getTollEstimate(start, end, vehicle.type || 'car', route.coordinates).catch(() => null),
        getRouteWeather(route.coordinates).catch(() => null),
        suggestRestStops(route.coordinates, route.durationMin, 2.5),
        buildItinerary(route.coordinates, route.durationMin, dailyDrivingHours, route.distanceKm),
        getDepartureAdvice(start, departAt).catch(() => null),
        getWikiPlaces(end.lat, end.lng, 10000, 5).catch(() => []),
        getDestinationEvents(end.lat, end.lng, end.name || '').catch(() => []),
      ]);

    const places: Record<string, any[]> = {};
    if (Array.isArray(includePlaces) && includePlaces.length > 0) {
      await Promise.all(
        includePlaces.map(async (cat: string) => {
          try {
            places[cat] = await findPlacesAlongRoute(route.coordinates, cat as any);
          } catch (_) {
            places[cat] = [];
          }
        })
      );
    }

    const budget = estimateBudget({
      distanceKm: route.distanceKm,
      estimatedDays,
      vehicle: {
        efficiencyKmPerLiter: vehicle.efficiencyKmPerLiter,
        fuelType: vehicle.fuelType,
      },
      toll,
    });

    return c.json({
      route,
      fuelPlan,
      estimatedDays,
      toll,
      weather,
      restStops,
      itinerary,
      departureAdvice,
      places,
      wikiPlaces,
      destinationEvents,
      budget,
      navigationWaypoints,
    });
  } catch (err: any) {
    console.error('Trip plan failed:', err?.message || err);
    return c.json({ error: 'Failed to plan trip', detail: err?.message }, 502);
  }
});

// GET /api/trip/reverse-geocode
trip.get('/reverse-geocode', async (c) => {
  const lat = c.req.query('lat');
  const lng = c.req.query('lng');
  if (!lat || !lng) return c.json({ error: 'Missing lat or lng' }, 400);

  const token = c.env.MAPBOX_TOKEN;
  if (token) {
    try {
      const url = `https://api.mapbox.com/geocoding/v5/mapbox.places/${lng},${lat}.json?access_token=${token}&limit=1&language=en`;
      const res = await fetch(url, { signal: AbortSignal.timeout(6000) });
      if (res.ok) {
        const data: any = await res.json();
        const feature = data?.features?.[0];
        return c.json({ address: feature ? feature.place_name : null });
      }
    } catch (_) {}
  }

  // Fallback to Nominatim
  try {
    const url = `https://nominatim.openstreetmap.org/reverse?lat=${lat}&lon=${lng}&format=json&zoom=18`;
    const res = await fetch(url, {
      headers: { 'User-Agent': 'Voyplan/1.0 (https://voyplan.in/)' },
      signal: AbortSignal.timeout(6000),
    });
    if (res.ok) {
      const data: any = await res.json();
      return c.json({ address: data?.display_name || null });
    }
  } catch (err: any) {
    return c.json({ error: 'Reverse geocoding failed', detail: err?.message }, 500);
  }

  return c.json({ address: null });
});

// POST /api/trip/pois
trip.post('/pois', async (c) => {
  const body = (await c.req.json().catch(() => ({}))) as any;
  const { coordinates, categories } = body;

  if (!coordinates || !Array.isArray(coordinates)) {
    return c.json({ error: 'coordinates must be an array of {lat, lng}' }, 400);
  }
  if (!categories || !Array.isArray(categories)) {
    return c.json({ error: 'categories must be an array of strings' }, 400);
  }

  try {
    const places = await findPOIsAlongRoute(coordinates, categories);
    return c.json({ places });
  } catch (err: any) {
    console.error('Failed to fetch POIs:', err?.message || err);
    return c.json({ error: 'Failed to fetch POIs', detail: err?.message }, 502);
  }
});

// POST /api/trip/save (requireAuth)
trip.post('/save', requireAuth, async (c) => {
  const supabase = c.get('supabase')!;
  const user = c.get('user')!;

  const body = (await c.req.json().catch(() => ({}))) as any;
  const {
    name,
    startPoint,
    endPoint,
    vehicleType,
    vehicle,
    waypoints,
    tripStart,
    itinerary,
    distanceKm,
    durationMinutes,
    fuelCost,
    tollCost,
    status: tripStatus,
  } = body;

  try {
    const enrichedEnd = { ...(endPoint || {}) };
    if (tripStart) enrichedEnd.tripStart = tripStart;
    if (itinerary && itinerary.length) enrichedEnd.itinerary = itinerary;
    if (vehicle && typeof vehicle === 'object') enrichedEnd.vehicle = vehicle;
    if (distanceKm != null) enrichedEnd.distanceKm = Number(distanceKm);
    if (durationMinutes != null) enrichedEnd.durationMinutes = Number(durationMinutes);
    if (fuelCost != null) enrichedEnd.fuelCost = Number(fuelCost);
    if (tollCost != null) enrichedEnd.tollCost = Number(tollCost);
    if (tripStatus) enrichedEnd.status = tripStatus;

    const { data, error } = await supabase
      .from('trips')
      .insert({
        user_id: user.id,
        ...(user.email ? { owner_email: String(user.email).toLowerCase() } : {}),
        name,
        start_point: startPoint,
        end_point: enrichedEnd,
        vehicle_type: vehicleType || 'car',
      })
      .select()
      .single();

    if (error) throw error;

    if (waypoints && waypoints.length > 0) {
      const stopsToInsert = waypoints.map((wp: any, i: number) => ({
        trip_id: data.id,
        type: wp.type || 'waypoint',
        lat: wp.lat,
        lng: wp.lng,
        name: wp.name,
        order_index: i,
      }));
      const { error: stopsError } = await supabase.from('trip_stops').insert(stopsToInsert);
      if (stopsError) {
        await supabase.from('trips').delete().eq('id', data.id);
        throw stopsError;
      }
    }

    return c.json({
      ...data,
      distanceKm: data.distanceKm ?? enrichedEnd.distanceKm,
      durationMinutes: data.durationMinutes ?? enrichedEnd.durationMinutes,
      fuelCost: data.fuelCost ?? enrichedEnd.fuelCost,
      tollCost: data.tollCost ?? enrichedEnd.tollCost,
      status: data.status ?? enrichedEnd.status ?? 'UPCOMING',
    });
  } catch (err: any) {
    console.error('Error saving trip:', err?.message || err);
    return c.json({ error: err?.message || 'Failed to save trip' }, 500);
  }
});

// GET /api/trip/saved (requireAuth)
trip.get('/saved', requireAuth, async (c) => {
  const supabase = c.get('supabase')!;

  try {
    const { data, error } = await supabase
      .from('trips')
      .select('*, trip_stops (*)')
      .order('created_at', { ascending: false });

    if (error) throw error;

    const active = (data || [])
      .filter((t: any) => t.status !== 'DELETED' && !t.deleted_at)
      .map((t: any) => {
        const endPt = t.end_point || {};
        return {
          ...t,
          distanceKm: t.distanceKm ?? endPt.distanceKm,
          durationMinutes: t.durationMinutes ?? endPt.durationMinutes,
          fuelCost: t.fuelCost ?? endPt.fuelCost,
          tollCost: t.tollCost ?? endPt.tollCost,
          status: t.status ?? endPt.status ?? 'UPCOMING',
        };
      });

    return c.json(active);
  } catch (err: any) {
    console.error('Error fetching saved trips:', err?.message || err);
    return c.json({ error: err?.message || 'Failed to fetch trips' }, 500);
  }
});

// PATCH /api/trip/:id (requireAuth)
trip.patch('/:id', requireAuth, async (c) => {
  const supabase = c.get('supabase')!;
  const id = c.req.param('id');
  const body = (await c.req.json().catch(() => ({}))) as any;
  const { status: patchStatus, name, endPoint } = body;

  try {
    const updateData: Record<string, any> = {};
    if (patchStatus) updateData.status = patchStatus;
    if (name) updateData.name = name;
    if (endPoint) updateData.end_point = endPoint;

    const { data, error } = await supabase
      .from('trips')
      .update(updateData)
      .eq('id', id)
      .select()
      .single();

    if (error) throw error;
    return c.json(data);
  } catch (err: any) {
    return c.json({ error: err?.message || 'Failed to update trip' }, 500);
  }
});

// DELETE /api/trip/:id (requireAuth)
trip.delete('/:id', requireAuth, async (c) => {
  const supabase = c.get('supabase')!;
  const id = c.req.param('id');

  try {
    const nowIso = new Date().toISOString();
    const { error: updateError } = await supabase
      .from('trips')
      .update({ status: 'DELETED', deleted_at: nowIso })
      .eq('id', id);

    const { error: deleteError } = await supabase.from('trips').delete().eq('id', id);

    if (updateError && deleteError) {
      throw deleteError || updateError;
    }

    return c.json({ success: true, id, status: 'DELETED', deleted_at: nowIso });
  } catch (err: any) {
    return c.json({ error: err?.message || 'Failed to delete trip' }, 500);
  }
});

// POST /api/trip/share
trip.post('/share', async (c) => {
  const body = (await c.req.json().catch(() => ({}))) as any;
  if (!body || typeof body !== 'object') {
    return c.json({ error: 'Trip data is required to generate share' }, 400);
  }

  try {
    const supabase = c.get('supabase') || null;
    const result = await createTripShare(body, supabase);
    return c.json(result);
  } catch (err: any) {
    return c.json({ error: 'Failed to generate share link' }, 500);
  }
});

// GET /api/trip/share/:shareId
trip.get('/share/:shareId', async (c) => {
  const shareId = c.req.param('shareId');
  try {
    const supabase = c.get('supabase') || null;
    const tripShare = await getTripShare(shareId, supabase);
    if (!tripShare) {
      return c.json({ error: 'Shared trip not found or expired' }, 404);
    }
    return c.json(tripShare);
  } catch (err: any) {
    return c.json({ error: 'Failed to fetch shared trip' }, 500);
  }
});

export default trip;
