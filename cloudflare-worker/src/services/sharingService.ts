import type { SupabaseClient } from '@supabase/supabase-js';

const memoryShares = new Map<string, { id: string; data: any; expiresAt: number }>();

export function sanitizeTripForShare(trip: any) {
  if (!trip || typeof trip !== 'object') return {};

  return {
    title: String(trip.title || trip.name || 'VoyPlan Journey'),
    tripType: String(trip.tripType || trip.type || 'one_way'),
    origin: trip.origin || trip.start || trip.start_point || null,
    destination: trip.destination || trip.end || trip.end_point || null,
    travelDate: trip.travelDate || trip.startDate || trip.tripStart || null,
    departureTime: trip.departureTime || trip.startTime || '08:00',
    travelers: Number(trip.travelers || trip.travellers) || 1,
    vehicle: trip.vehicle
      ? {
          name: trip.vehicle.name || 'Vehicle',
          type: trip.vehicle.type || 'car',
          fuelType: trip.vehicle.fuelType || 'petrol',
          mileage: trip.vehicle.mileage || trip.vehicle.efficiencyKmPerLiter || 15,
          tankCapacity: trip.vehicle.tankCapacity || trip.vehicle.tankCapacityLiters || 45,
          currentFuel: trip.vehicle.currentFuel || trip.vehicle.currentFuelLiters || 20,
        }
      : null,
    distanceKm: Number(trip.distanceKm || trip.totalDistanceKm) || 0,
    durationMin: Number(trip.durationMin || trip.totalDurationMin) || 0,
    stops: Array.isArray(trip.stops)
      ? trip.stops.map((s: any) => ({
          name: s.name || 'Stop',
          lat: s.lat ?? s.latitude,
          lng: s.lng ?? s.longitude,
          category: s.category || s.type || 'attraction',
          stayDuration: s.stayDuration || s.durationMin || 30,
        }))
      : [],
    fuelStops: Array.isArray(trip.fuelStops)
      ? trip.fuelStops.map((f: any) => ({
          name: f.name || 'Refuel Station',
          lat: f.lat ?? f.latitude,
          lng: f.lng ?? f.longitude,
          distanceFromStartKm: f.distanceFromStartKm || 0,
          refillLiters: f.refillLiters || 0,
          estimatedCost: f.estimatedCost || 0,
        }))
      : [],
    budget: trip.budget
      ? {
          total: trip.budget.total || 0,
          perPerson:
            trip.budget.perPerson ||
            Math.round((trip.budget.total || 0) / Math.max(1, Number(trip.travelers || 1))),
          fuel: trip.budget.fuel || trip.budget.breakdown?.fuel || 0,
          tolls: trip.budget.tolls || trip.budget.breakdown?.tolls || 0,
          food: trip.budget.food || trip.budget.breakdown?.food || 0,
          stay: trip.budget.stay || trip.budget.breakdown?.stay || 0,
          activities: trip.budget.activities || trip.budget.breakdown?.activities || 0,
          miscellaneous: trip.budget.miscellaneous || trip.budget.breakdown?.miscellaneous || 0,
        }
      : null,
    itinerary: Array.isArray(trip.itinerary) ? trip.itinerary : Array.isArray(trip.days) ? trip.days : [],
    createdAt: new Date().toISOString(),
  };
}

export async function createTripShare(tripData: any, supabase?: SupabaseClient | null) {
  const randomHex = crypto.randomUUID().replace(/-/g, '').substring(0, 16);
  const shareId = `voy_${randomHex}`;
  const sanitized = sanitizeTripForShare(tripData);

  memoryShares.set(shareId, {
    id: shareId,
    data: sanitized,
    expiresAt: Date.now() + 30 * 24 * 60 * 60 * 1000,
  });

  if (supabase) {
    try {
      await supabase.from('route_cache').insert({
        route_hash: `share_${shareId}`,
        polyline: sanitized,
        distance_km: sanitized.distanceKm,
        duration_min: sanitized.durationMin,
        toll_data: { shareId, title: sanitized.title },
      });
    } catch (_) {}
  }

  return {
    shareId,
    shareUrl: `https://voyplan.in/trip/share/${shareId}`,
    trip: sanitized,
  };
}

export async function getTripShare(shareId: string, supabase?: SupabaseClient | null) {
  if (!shareId) return null;

  const cached = memoryShares.get(shareId);
  if (cached && cached.expiresAt > Date.now()) {
    return cached.data;
  }

  if (supabase) {
    try {
      const { data } = await supabase
        .from('route_cache')
        .select('polyline')
        .eq('route_hash', `share_${shareId}`)
        .maybeSingle();

      if (data && data.polyline) {
        memoryShares.set(shareId, {
          id: shareId,
          data: data.polyline,
          expiresAt: Date.now() + 30 * 24 * 60 * 60 * 1000,
        });
        return data.polyline;
      }
    } catch (_) {}
  }

  return null;
}
