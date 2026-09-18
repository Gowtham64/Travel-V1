const PHOTON_TERMS: Record<string, string[]> = {
  // Food
  restaurant: ['restaurant', 'veg restaurant', 'dhaba', 'hotel dining', 'bhavan'],
  cafe: ['cafe', 'coffee shop', 'tea stall', 'cafe coffee day', 'bakery'],
  vegetarian: ['pure veg restaurant', 'veg hotel', 'bhavan', 'vegetarian', 'veg dining'],
  non_vegetarian: ['non veg restaurant', 'biryani', 'dhaba', 'chicken', 'meat'],
  local_food: ['local cuisine', 'traditional food', 'mess', 'thali', 'dhaba'],
  fast_food: ['fast food', 'burger', 'pizza', 'snacks', 'chaat'],
  dining: ['restaurant', 'veg restaurant', 'dhaba', 'cafe'],
  tea: ['tea stall', 'chai point', 'cafe', 'bakery'],

  // Attractions & Sights
  attraction: ['palace', 'fort', 'monument', 'landmark', 'tourist attraction'],
  famous_places: ['famous place', 'monument', 'palace', 'fort', 'heritage site'],
  viewpoint: ['viewpoint', 'hill viewpoint', 'lookout', 'scenic point'],
  historical: ['historical site', 'fort', 'palace', 'ruins', 'monument', 'heritage'],
  temple: ['sri temple', 'swamy temple', 'temple', 'mandir', 'kovil'],
  church: ['church', 'cathedral', 'basilica', 'chapel'],
  waterfall: ['waterfall', 'falls', 'cascade'],
  beach: ['beach', 'sea shore', 'coastline'],
  park: ['park', 'botanical garden', 'national park', 'nature park'],
  museum: ['museum', 'art gallery', 'exhibition center'],
  photography: ['scenic viewpoint', 'photo spot', 'sunset point', 'sunrise point'],
  nature: ['nature reserve', 'forest', 'wildlife sanctuary', 'hills', 'lake'],
  hills: ['hills', 'peak', 'viewpoint', 'hill station'],
  lake: ['lake', 'dam', 'reservoir'],
  river: ['river', 'waterfall', 'stream'],

  // Travel Services & Lodging
  fuel: ['petrol pump', 'indian oil', 'bharat petroleum', 'hindustan petroleum', 'shell petrol', 'fuel'],
  charging: ['ev charging', 'tata power ev', 'charging station', 'electric vehicle'],
  restroom: ['public toilet', 'restroom', 'washroom', 'comfort station'],
  parking: ['parking', 'car parking', 'parking lot'],
  atm: ['atm', 'bank atm', 'cash machine'],
  hospital: ['hospital', 'clinic', 'emergency medical', 'healthcare'],
  hotel: ['resort', 'hotel stay', 'lodge', 'inn', 'homestay'],
};

function distKm(lat1: number, lon1: number, lat2: number, lon2: number) {
  const p = Math.PI / 180;
  const a =
    0.5 -
    Math.cos((lat2 - lat1) * p) / 2 +
    (Math.cos(lat1 * p) * Math.cos(lat2 * p) * (1 - Math.cos((lon2 - lon1) * p))) / 2;
  return 12742 * Math.asin(Math.sqrt(a));
}

function sampleCoordinates(coords: any[], maxPoints = 7) {
  if (!coords || coords.length <= maxPoints) return coords || [];
  const step = Math.floor(coords.length / maxPoints);
  const sampled = [];
  for (let i = 0; i < coords.length; i += step) {
    sampled.push(coords[i]);
  }
  if (sampled[sampled.length - 1] !== coords[coords.length - 1]) {
    sampled.push(coords[coords.length - 1]);
  }
  return sampled;
}

export async function findPOIsAlongRoute(routeCoords: any[] = [], categories: string[] = []) {
  if (!routeCoords || routeCoords.length < 2) return {};

  const normCoords = routeCoords.map((c: any) => {
    if (Array.isArray(c)) return { lat: c[1], lng: c[0] };
    return { lat: c.lat ?? c.latitude, lng: c.lng ?? c.longitude };
  });

  const samples = sampleCoordinates(normCoords, 6);
  const places: Record<string, any[]> = {};

  for (const category of categories) {
    const terms = PHOTON_TERMS[category] || [category];
    const results: any[] = [];
    const seenKeys = new Set<string>();
    const fetchPromises = [];

    for (const pt of samples) {
      for (const term of terms) {
        const url = `https://photon.komoot.io/api/?q=${encodeURIComponent(term)}&lat=${pt.lat}&lon=${pt.lng}&limit=8`;
        fetchPromises.push(
          fetch(url, { signal: AbortSignal.timeout(4000) })
            .then(async (res) => {
              if (!res.ok) return;
              const data: any = await res.json();
              const feats = data?.features || [];
              for (const f of feats) {
                const geom = f.geometry?.coordinates || [];
                const p = f.properties || {};
                let name = (p.name || '').trim();
                if (geom.length >= 2) {
                  const lng = geom[0];
                  const lat = geom[1];

                  let minDetour = Infinity;
                  for (const sp of samples) {
                    const d = distKm(lat, lng, sp.lat, sp.lng);
                    if (d < minDetour) minDetour = d;
                  }
                  if (minDetour > 12.0) continue;

                  const city = p.city || p.district || p.county || p.locality;
                  if (!name || name.toLowerCase() === 'temple' || name.toLowerCase() === 'place_of_worship') {
                    if (category === 'temple') {
                      name = city ? `Sri Temple (${city})` : 'Sri Temple';
                    } else if (category === 'fuel') {
                      name = city ? `Fuel Station (${city})` : 'Fuel Station';
                    } else {
                      name = city ? `${term.toUpperCase()} (${city})` : term.toUpperCase();
                    }
                  }

                  const key = `${name}-${lat.toFixed(3)}-${lng.toFixed(3)}`;
                  if (!seenKeys.has(key)) {
                    seenKeys.add(key);
                    const addrParts = [p.street, city, p.state].filter(Boolean);
                    const addr = addrParts.length > 0 ? addrParts.join(', ') : `${name}`;

                    const isTemple = category === 'temple' || /temple|swamy|kovil|gudi|mandir/i.test(name);
                    results.push({
                      id: p.osm_id || Math.floor(Math.random() * 1000000),
                      name,
                      lat,
                      lng,
                      address: addr,
                      rating: isTemple ? 4.8 : category === 'attraction' ? 4.6 : 4.4,
                      categoryType: isTemple ? '🛕 Hindu temple' : category === 'attraction' ? '📍 Landmark' : '📌 Stop',
                      timing: isTemple ? 'Opens 5:00 AM · Closes 9:00 PM' : null,
                    });
                  }
                }
              }
            })
            .catch(() => {})
        );
      }
    }

    await Promise.all(fetchPromises);
    places[category] = results;
  }

  return places;
}

export async function findPOIsInArea(center: any, categories: string[] = [], radiusKm = 25) {
  if (!center || !Number.isFinite(center.lat) || !Number.isFinite(center.lng)) return [];
  const results: any[] = [];
  const seenKeys = new Set<string>();
  const fetchPromises = [];

  for (const category of categories) {
    const terms = PHOTON_TERMS[category] || [category];
    for (const term of terms) {
      const url = `https://photon.komoot.io/api/?q=${encodeURIComponent(term)}&lat=${center.lat}&lon=${center.lng}&limit=12`;
      fetchPromises.push(
        fetch(url, { signal: AbortSignal.timeout(4000) })
          .then(async (res) => {
            if (!res.ok) return;
            const data: any = await res.json();
            const feats = data?.features || [];
            for (const f of feats) {
              const geom = f.geometry?.coordinates || [];
              const p = f.properties || {};
              let name = (p.name || '').trim();
              if (geom.length >= 2) {
                const lng = geom[0];
                const lat = geom[1];
                const d = distKm(center.lat, center.lng, lat, lng);
                if (d > radiusKm) continue;

                const city = p.city || p.district || p.county || p.locality || center.city || '';
                if (!name || name.toLowerCase() === 'temple' || name.toLowerCase() === 'place_of_worship') {
                  if (category === 'temple') {
                    name = city ? `Sri Temple (${city})` : 'Sri Temple';
                  } else {
                    name = city ? `${term.toUpperCase()} (${city})` : term.toUpperCase();
                  }
                }

                const key = `${name.toLowerCase()}-${lat.toFixed(3)}-${lng.toFixed(3)}`;
                if (!seenKeys.has(key)) {
                  seenKeys.add(key);
                  const addrParts = [p.street, city, p.state].filter(Boolean);
                  const addr = addrParts.length > 0 ? addrParts.join(', ') : `${name}, ${city}`;
                  const placeId = p.osm_id ? `osm_${p.osm_type || 'p'}_${p.osm_id}` : `osm_${lat.toFixed(4)}_${lng.toFixed(4)}`;
                  const isTemple = category === 'temple' || /temple|swamy|kovil|gudi|mandir/i.test(name);
                  results.push({
                    placeId,
                    name,
                    lat,
                    lng,
                    latitude: lat,
                    longitude: lng,
                    address: addr,
                    city,
                    state: p.state || '',
                    country: p.country || 'India',
                    category: isTemple ? 'temples' : category,
                    categories: [isTemple ? 'temples' : category, 'famous_places'],
                    rating: isTemple ? 4.8 : 4.5,
                    destinationDistanceKm: Math.round(d * 10) / 10,
                    distanceFromDestKm: Math.round(d * 10) / 10,
                    source: 'osm_photon',
                  });
                }
              }
            }
          })
          .catch(() => {})
      );
    }
  }

  await Promise.all(fetchPromises);
  return results;
}
