const { haversineDistanceKm } = require("../utils/geo");
const { getRoute, toPoint } = require("./routingService");
const { geocodeAddress } = require("./geocodeService");
const { geocode, route: osrmRoute } = require("./itineraryGeo");
const { findPOIsInArea } = require("./orsPoiService");
const FuelRangeService = require("./fuelRangeService");
const { rankCandidatesWithAI, getBestCuratedVenue } = require("./aiService");
const curatedPlaces = require("../data/curatedPlaces.json");
const { calculateTripRoute } = require("./routeCalculationService");

/**
 * Category-based standard visit durations (minutes)
 */
const CATEGORY_DURATIONS = {
  viewpoints: 30,
  temples: 55,
  historical_heritage: 85,
  forts_palaces: 90,
  museums: 75,
  waterfalls_rivers: 60,
  hills_mountains: 45,
  beaches: 60,
  wildlife_national_parks: 90,
  nature_forests: 60,
  monuments_landmarks: 45,
  city_attractions: 45,
  bridges_dams: 40,
  markets_local: 60,
  cultural_places: 60,
  photography_spots: 30,
  famous_places: 60,
  default: 45,
};

/**
 * Parse time string to minutes from midnight (0 - 1439).
 * Handles: "14:00", "02:00 PM", "2:00 pm", "2:00AM", "8:30", "08:30"
 */
function parseMinutes(str) {
  if (!str) return 480; // default 08:00 AM
  const clean = String(str).trim();
  const isPM = /pm/i.test(clean);
  const isAM = /am/i.test(clean);
  const parts = clean.replace(/[^\d:]/g, "").split(":");
  let h = parseInt(parts[0], 10) || 0;
  const m = parseInt(parts[1], 10) || 0;

  if (isPM && h < 12) h += 12;
  if (isAM && h === 12) h = 0;

  return Math.max(0, Math.min(h * 60 + m, 1439));
}

/**
 * Format minutes from midnight to standard 12-hour AM/PM display string.
 * e.g. 840 -> "02:00 PM", 510 -> "08:30 AM"
 */
function formatMinutes(min) {
  const norm = ((min % 1440) + 1440) % 1440;
  const h24 = Math.floor(norm / 60);
  const m = norm % 60;
  const ampm = h24 < 12 ? "AM" : "PM";
  let h12 = h24 % 12;
  if (h12 === 0) h12 = 12;
  const hStr = h12.toString().padStart(2, "0");
  const mStr = m.toString().padStart(2, "0");
  return `${hStr}:${mStr} ${ampm}`;
}

/**
 * Format minutes to 24-hour HH:mm string.
 */
function format24h(min) {
  const norm = ((min % 1440) + 1440) % 1440;
  const h24 = Math.floor(norm / 60);
  const m = norm % 60;
  return `${h24.toString().padStart(2, "0")}:${m.toString().padStart(2, "0")}`;
}

const MAJOR_CITIES = {
  bengaluru: { lat: 12.9716, lng: 77.5946, name: "Bengaluru", city: "Bengaluru", state: "Karnataka", country: "India" },
  bangalore: { lat: 12.9716, lng: 77.5946, name: "Bengaluru", city: "Bengaluru", state: "Karnataka", country: "India" },
  mysuru: { lat: 12.2958, lng: 76.6394, name: "Mysuru", city: "Mysuru", state: "Karnataka", country: "India" },
  mysore: { lat: 12.2958, lng: 76.6394, name: "Mysuru", city: "Mysuru", state: "Karnataka", country: "India" },
  tirupati: { lat: 13.6288, lng: 79.4192, name: "Tirupati", city: "Tirupati", state: "Andhra Pradesh", country: "India" },
  tirumala: { lat: 13.6833, lng: 79.3473, name: "Tirumala", city: "Tirupati", state: "Andhra Pradesh", country: "India" },
  coorg: { lat: 12.4244, lng: 75.7382, name: "Madikeri (Coorg)", city: "Coorg", state: "Karnataka", country: "India" },
  madikeri: { lat: 12.4244, lng: 75.7382, name: "Madikeri (Coorg)", city: "Coorg", state: "Karnataka", country: "India" },
  ooty: { lat: 11.4102, lng: 76.6950, name: "Ooty", city: "Ooty", state: "Tamil Nadu", country: "India" },
  chennai: { lat: 13.0827, lng: 80.2707, name: "Chennai", city: "Chennai", state: "Tamil Nadu", country: "India" },
  hyderabad: { lat: 17.3850, lng: 78.4867, name: "Hyderabad", city: "Hyderabad", state: "Telangana", country: "India" },
  mumbai: { lat: 19.0760, lng: 72.8777, name: "Mumbai", city: "Mumbai", state: "Maharashtra", country: "India" },
  goa: { lat: 15.2993, lng: 74.1240, name: "Goa", city: "Goa", state: "Goa", country: "India" },
  delhi: { lat: 28.6139, lng: 77.2090, name: "Delhi", city: "Delhi", state: "Delhi", country: "India" },
  srirangapatna: { lat: 12.4237, lng: 76.6853, name: "Srirangapatna", city: "Srirangapatna", state: "Karnataka", country: "India" },
  madurai: { lat: 9.9252, lng: 78.1198, name: "Madurai", city: "Madurai", state: "Tamil Nadu", country: "India" },
  tiruchirappalli: { lat: 10.7905, lng: 78.7047, name: "Tiruchirappalli", city: "Tiruchirappalli", state: "Tamil Nadu", country: "India" },
  trichy: { lat: 10.7905, lng: 78.7047, name: "Tiruchirappalli", city: "Tiruchirappalli", state: "Tamil Nadu", country: "India" },
  thanjavur: { lat: 10.7870, lng: 79.1378, name: "Thanjavur", city: "Thanjavur", state: "Tamil Nadu", country: "India" },
  dindigul: { lat: 10.3673, lng: 77.9803, name: "Dindigul", city: "Dindigul", state: "Tamil Nadu", country: "India" },
  rameswaram: { lat: 9.2876, lng: 79.3129, name: "Rameswaram", city: "Rameswaram", state: "Tamil Nadu", country: "India" },
  kodaikanal: { lat: 10.2381, lng: 77.4892, name: "Kodaikanal", city: "Kodaikanal", state: "Tamil Nadu", country: "India" },
  pondicherry: { lat: 11.9416, lng: 79.8083, name: "Puducherry", city: "Puducherry", state: "Puducherry", country: "India" },
  salem: { lat: 11.6643, lng: 78.1460, name: "Salem", city: "Salem", state: "Tamil Nadu", country: "India" },
  vellore: { lat: 12.9165, lng: 79.1325, name: "Vellore", city: "Vellore", state: "Tamil Nadu", country: "India" },
  tirunelveli: { lat: 8.7139, lng: 77.7567, name: "Tirunelveli", city: "Tirunelveli", state: "Tamil Nadu", country: "India" },
  kanyakumari: { lat: 8.0883, lng: 77.5385, name: "Kanyakumari", city: "Kanyakumari", state: "Tamil Nadu", country: "India" },
  coimbatore: { lat: 11.0168, lng: 76.9558, name: "Coimbatore", city: "Coimbatore", state: "Tamil Nadu", country: "India" },
};

/**
 * Safely extracts a clean string name from any location representation.
 * Under NO circumstances does this return "[object Object]".
 */
function extractLocationName(loc, fallback = "") {
  if (!loc) return fallback;
  if (typeof loc === "string") {
    const trimmed = loc.trim();
    if (!trimmed || trimmed === "[object Object]" || trimmed.includes("[object Object]")) {
      return fallback;
    }
    return trimmed;
  }
  if (typeof loc === "object") {
    // 1. Direct name
    if (loc.name) {
      const n = extractLocationName(loc.name, "");
      if (n) return n;
    }
    // 2. Title
    if (loc.title) {
      const t = extractLocationName(loc.title, "");
      if (t) return t;
    }
    // 3. Nested location or place
    if (loc.location) {
      const l = extractLocationName(loc.location, "");
      if (l) return l;
    }
    if (loc.place) {
      const p = extractLocationName(loc.place, "");
      if (p) return p;
    }
    // 4. City
    if (loc.city) {
      const c = extractLocationName(loc.city, "");
      if (c) return c;
    }
    // 5. Address (first segment)
    if (loc.address) {
      const a = extractLocationName(loc.address, "");
      if (a) return a.split(",")[0].trim();
    }
  }
  return fallback;
}

/**
 * Standardizes any location into the Canonical Location Model:
 * {
 *   id: string,
 *   name: string,
 *   placeId: string,
 *   address: string,
 *   latitude: number,
 *   longitude: number,
 *   lat: number,
 *   lng: number,
 *   city: string,
 *   state: string,
 *   country: string,
 *   type: string,
 *   locked: boolean,
 *   userSelected: boolean
 * }
 */
function normalizeCanonicalLocation(loc, defaultName = "Stop") {
  if (!loc) return null;
  const name = extractLocationName(loc, defaultName);
  let lat = null;
  let lng = null;
  let placeId = "";
  let address = name;
  let city = "";
  let state = "";
  let country = "India";
  let type = "place";
  let locked = false;
  let userSelected = false;

  if (typeof loc === "object") {
    const rawLat = Number(loc.latitude ?? loc.lat);
    const rawLng = Number(loc.longitude ?? loc.lng ?? loc.lon);
    if (Number.isFinite(rawLat) && Number.isFinite(rawLng) && (rawLat !== 0 || rawLng !== 0)) {
      lat = rawLat;
      lng = rawLng;
    }
    placeId = String(loc.placeId || loc.id || "");
    if (loc.address) address = extractLocationName(loc.address, name);
    if (loc.city) city = extractLocationName(loc.city, "");
    if (loc.state) state = extractLocationName(loc.state, "");
    if (loc.country) country = extractLocationName(loc.country, "India");
    if (loc.type) type = String(loc.type);
    locked = loc.locked === true;
    userSelected = loc.userSelected !== false;
  }

  const resolvedPlaceId = placeId || `pl_${name.toLowerCase().replace(/[^a-z0-9]/g, "_")}_${Math.round((lat || 0) * 1000)}`;

  return {
    id: resolvedPlaceId,
    name,
    placeId: resolvedPlaceId,
    address: address || name,
    latitude: lat,
    longitude: lng,
    lat,
    lng,
    city: city || name,
    state: state || "",
    country: country || "India",
    type,
    locked,
    userSelected,
  };
}

/**
 * Robust geocoding for a place name, optionally focused around a reference point.
 * Guarantees never to query or return "[object Object]".
 */
async function resolveLocation(nameOrCoord, fallbackName = "Stop", focus = null) {
  if (!nameOrCoord) return null;

  // 1. If it's already an object with finite coordinates and a valid name:
  if (typeof nameOrCoord === "object") {
    const lat = Number(nameOrCoord.lat ?? nameOrCoord.latitude);
    const lng = Number(nameOrCoord.lng ?? nameOrCoord.longitude ?? nameOrCoord.lon);
    const pName = extractLocationName(nameOrCoord, fallbackName);

    if (Number.isFinite(lat) && Number.isFinite(lng) && lat !== 0 && lng !== 0) {
      const placeId = nameOrCoord.placeId || `pl_${pName.toLowerCase().replace(/[^a-z0-9]/g, '_')}_${Math.round(lat * 1000)}_${Math.round(lng * 1000)}`;
      return {
        lat,
        lng,
        latitude: lat,
        longitude: lng,
        placeId,
        id: placeId,
        name: pName,
        address: extractLocationName(nameOrCoord.address, pName),
        city: extractLocationName(nameOrCoord.city, pName),
        state: extractLocationName(nameOrCoord.state, ""),
        country: extractLocationName(nameOrCoord.country, "India"),
        type: nameOrCoord.type || "place",
        locked: nameOrCoord.locked === true,
        userSelected: nameOrCoord.userSelected !== false,
      };
    }
  }

  // 2. Extract a safe text query. NEVER String(nameOrCoord) directly if it evaluates to "[object Object]"
  const query = extractLocationName(nameOrCoord, "");
  if (!query || query === "[object Object]" || query.includes("[object Object]")) {
    return null;
  }

  const qLower = query.toLowerCase();

  // 3. Instant check for major cities with word-boundary matching
  for (const [key, cityInfo] of Object.entries(MAJOR_CITIES)) {
    const isExact = qLower === key;
    const isWordMatch = new RegExp(`(^|[\\s,.-])${key}([\\s,.-]|$)`, "i").test(qLower);
    if (isExact || isWordMatch) {
      return {
        lat: cityInfo.lat,
        lng: cityInfo.lng,
        latitude: cityInfo.lat,
        longitude: cityInfo.lng,
        placeId: `city_${key}`,
        id: `city_${key}`,
        name: cityInfo.name,
        address: `${cityInfo.name}, ${cityInfo.state}`,
        city: cityInfo.city,
        state: cityInfo.state,
        country: cityInfo.country,
        type: "city",
        locked: true,
        userSelected: true,
      };
    }
  }

  // 4. Check curated places first for exact or high-confidence match
  const curatedMatch = curatedPlaces.find((p) => {
    const pLower = p.name.toLowerCase();
    return pLower === qLower || (qLower.length >= 6 && pLower.startsWith(qLower));
  });

  if (curatedMatch) {
    return {
      lat: curatedMatch.lat,
      lng: curatedMatch.lng,
      latitude: curatedMatch.lat,
      longitude: curatedMatch.lng,
      placeId: curatedMatch.id || `curated_${curatedMatch.name.toLowerCase().replace(/[^a-z0-9]/g, '_')}`,
      id: curatedMatch.id || `curated_${curatedMatch.name.toLowerCase().replace(/[^a-z0-9]/g, '_')}`,
      name: curatedMatch.name,
      address: `${curatedMatch.name}, ${curatedMatch.city}, ${curatedMatch.state}`,
      city: curatedMatch.city,
      state: curatedMatch.state,
      country: curatedMatch.country,
      category: curatedMatch.category,
      categories: curatedMatch.categories,
      openingHours: curatedMatch.openingHours,
      visitDurationMin: curatedMatch.visitDurationMin,
      type: "attraction",
    };
  }

  // 5. Geocode via ORS / Mapbox with clean text query
  try {
    const geo = focus ? await geocode(query, "", focus) : null;
    if (geo && Number.isFinite(geo.lat) && Number.isFinite(geo.lng) && (geo.lat !== 0 || geo.lng !== 0)) {
      return {
        lat: geo.lat,
        lng: geo.lng,
        latitude: geo.lat,
        longitude: geo.lng,
        placeId: `geo_${Math.round(geo.lat * 1000)}_${Math.round(geo.lng * 1000)}`,
        id: `geo_${Math.round(geo.lat * 1000)}_${Math.round(geo.lng * 1000)}`,
        name: query,
        address: query,
        city: "",
        state: "",
        country: "India",
        type: "place",
      };
    }
  } catch (_) {}

  try {
    const addr = await geocodeAddress(query);
    if (addr && Number.isFinite(addr.lat) && Number.isFinite(addr.lng) && (addr.lat !== 0 || addr.lng !== 0)) {
      return {
        lat: addr.lat,
        lng: addr.lng,
        latitude: addr.lat,
        longitude: addr.lng,
        placeId: `addr_${Math.round(addr.lat * 1000)}_${Math.round(addr.lng * 1000)}`,
        id: `addr_${Math.round(addr.lat * 1000)}_${Math.round(addr.lng * 1000)}`,
        name: query,
        address: addr.displayName || query,
        city: "",
        state: "",
        country: "India",
        type: "place",
      };
    }
  } catch (_) {}

  return null;
}

/**
 * Route between two points using authoritative road routing engine.
 * Returns exact road distanceKm, travelMin, and coordinate geometry.
 */
async function routeBetweenPoints(from, to) {
  if (!from || !to) return { distanceKm: 0, travelMin: 0, coordinates: [] };

  try {
    const res = await getRoute(from, to, [], { avoidMotorways: false });
    if (res && res.distanceKm > 0) {
      return {
        distanceKm: Math.round(res.distanceKm * 10) / 10,
        travelMin: Math.max(2, Math.round(res.durationMin || (res.distanceKm / 50) * 60)),
        coordinates: res.coordinates || [],
      };
    }
  } catch (_) {}

  // OSRM fallback
  try {
    const osrm = await osrmRoute(from, to);
    if (osrm && osrm.km > 0) {
      return {
        distanceKm: osrm.km,
        travelMin: Math.max(2, osrm.min),
        coordinates: [],
      };
    }
  } catch (_) {}

  // Great-circle distance + realistic Indian road winding factor (1.30) @ 48 km/h avg
  const directKm = haversineDistanceKm(from, to);
  const roadKm = Math.round(directKm * 1.3 * 10) / 10;
  const minutes = Math.max(3, Math.round((roadKm / 48) * 60));
  return { distanceKm: roadKm, travelMin: minutes, coordinates: [] };
}

/**
 * 2-Opt and Nearest-Neighbor sequence optimizer to minimize backtracking.
 *
 * For One-Way: Start is fixed at 0, Destination is fixed at end.
 * For Around: Start is fixed at 0, Return to Start is fixed at end.
 */
function optimizeStopSequence({ start, end, stops, isAroundTrip }) {
  if (!Array.isArray(stops) || stops.length <= 1) return stops || [];

  const unvisited = [...stops];
  const ordered = [];
  let current = start;

  // 1. Nearest-Neighbor greedy construction
  while (unvisited.length > 0) {
    let bestIdx = 0;
    let bestDist = Infinity;

    for (let i = 0; i < unvisited.length; i++) {
      const d = haversineDistanceKm(current, unvisited[i]);
      if (d < bestDist) {
        bestDist = d;
        bestIdx = i;
      }
    }

    const next = unvisited.splice(bestIdx, 1)[0];
    ordered.push(next);
    current = next;
  }

  // 2. 2-Opt refinement on the ordered intermediate stops
  function totalPathKm(list) {
    let km = haversineDistanceKm(start, list[0]);
    for (let i = 0; i < list.length - 1; i++) {
      km += haversineDistanceKm(list[i], list[i + 1]);
    }
    km += haversineDistanceKm(list[list.length - 1], end);
    return km;
  }

  let improved = true;
  let iterations = 0;
  while (improved && iterations < 30) {
    improved = false;
    iterations++;
    const currentCost = totalPathKm(ordered);

    for (let i = 0; i < ordered.length - 1; i++) {
      for (let k = i + 1; k < ordered.length; k++) {
        // Reverse slice between i and k
        const candidate = [
          ...ordered.slice(0, i),
          ...ordered.slice(i, k + 1).reverse(),
          ...ordered.slice(k + 1),
        ];
        const newCost = totalPathKm(candidate);
        if (newCost < currentCost - 0.2) {
          ordered.splice(0, ordered.length, ...candidate);
          improved = true;
          break;
        }
      }
      if (improved) break;
    }
  }

  return ordered;
}

/**
 * Filter and score candidate places against user category constraints.
 * Enforces destination anchoring, origin city exclusion, and corridor detour limits.
 */
function filterAndScoreCandidates({
  candidates,
  selectedCategories = [],
  categoryPriorities = {},
  baseAxisStart,
  baseAxisEnd,
  searchRadiusKm = 25,
}) {
  if (!Array.isArray(candidates) || candidates.length === 0) return [];

  const selectedSet = new Set(
    selectedCategories.map((c) => c.toLowerCase().trim().replace(/[^a-z0-9]/g, "_"))
  );
  const hasCategoryFilter = selectedSet.size > 0;
  const directDist = haversineDistanceKm(baseAxisStart, baseAxisEnd);
  const isLocalTrip = directDist <= 30;

  const valid = [];
  for (const c of candidates) {
    if (!c.lat || !c.lng) continue;

    const placeCategories = [
      c.category,
      ...(Array.isArray(c.categories) ? c.categories : []),
    ]
      .filter(Boolean)
      .map((cat) => cat.toLowerCase().trim().replace(/[^a-z0-9]/g, "_"));

    // 1. Strict Category Match Check
    let matches = !hasCategoryFilter;
    let priorityScore = 50;

    if (hasCategoryFilter) {
      for (const pCat of placeCategories) {
        if (selectedSet.has(pCat)) {
          matches = true;
          const prio = categoryPriorities[pCat] || "must_visit";
          if (prio === "must_visit") priorityScore = Math.max(priorityScore, 100);
          else if (prio === "would_like") priorityScore = Math.max(priorityScore, 70);
          else priorityScore = Math.max(priorityScore, 40);
        }
      }
    }

    // Do NOT add malls, movie theatres, or unrequested attractions unless explicitly matching
    if (!matches && !c.isUserSpecified && !c.isDestinationAnchor) continue;

    // 2. Destination Relevance & Corridor Detour Check
    const distToDest = haversineDistanceKm(baseAxisEnd, c);
    const distToStart = haversineDistanceKm(baseAxisStart, c);

    const isNearDest = distToDest <= searchRadiusKm;
    const isNearStart = isLocalTrip && distToStart <= searchRadiusKm;

    // Highway Corridor Detour Check:
    // Stops along the corridor must be genuine midway transit stops:
    // - Not in the starting origin city (distToStart > 30 km for long-distance trips)
    // - Between start and destination (distToStart <= directDist * 1.05 && distToDest <= directDist * 1.05)
    // - Minimal detour off the direct route (corridorDetour <= 15 km)
    const corridorDetour = distToStart + distToDest - directDist;
    const isAlongCorridor =
      !isLocalTrip &&
      directDist > 50 &&
      distToStart > 30 &&
      distToDest > searchRadiusKm &&
      distToStart <= directDist * 1.05 &&
      distToDest <= directDist * 1.05 &&
      corridorDetour <= 15;

    // Reject places from unrelated regions!
    if (!isNearDest && !isNearStart && !isAlongCorridor && !c.isUserSpecified && !c.isDestinationAnchor) {
      continue;
    }

    // Score: Destination itself / Destination-proximate places get highest priority boost, then corridor stops
    let locScore = 0;
    if (c.isDestinationAnchor) {
      locScore = 1000;
    } else if (isNearDest) {
      locScore = 500 - distToDest * 2.0; // Closer to destination center = higher rank
    } else if (isAlongCorridor) {
      locScore = 200 - corridorDetour * 5.0; // Minimal detour on highway corridor
    } else {
      locScore = 50;
    }

    const totalScore = priorityScore + locScore + (c.rating ? c.rating * 5 : 20);
    const placeId = c.placeId || `pl_${Math.round(c.lat * 10000)}_${Math.round(c.lng * 10000)}`;

    valid.push({
      ...c,
      placeId,
      latitude: c.lat,
      longitude: c.lng,
      destinationDistanceKm: Math.round(distToDest * 10) / 10,
      distanceFromDestKm: Math.round(distToDest * 10) / 10,
      detourKm: Math.round(corridorDetour * 10) / 10,
      score: totalScore,
    });
  }

  // Sort by score descending and deduplicate by placeId and coordinates
  valid.sort((a, b) => b.score - a.score);

  const deduplicated = [];
  const seenPlaceIds = new Set();
  for (const p of valid) {
    if (seenPlaceIds.has(p.placeId)) continue;
    const isDup = deduplicated.some(
      (existing) =>
        haversineDistanceKm(existing, p) < 0.25 ||
        existing.name.toLowerCase().trim() === p.name.toLowerCase().trim()
    );
    if (!isDup) {
      seenPlaceIds.add(p.placeId);
      deduplicated.push(p);
    }
  }

  return deduplicated;
}

/**
 * Main Deterministic Itinerary Planning Engine.
 *
 * Implements the full destination-based Around Trip pipeline:
 * 1. Validate inputs
 * 2. Geocode origin & destination (Destination is primary anchor)
 * 3. Discover candidates matching categories within search radius
 * 4. Optimize stop sequence (TSP 2-opt)
 * 5. Road routing between consecutive stops
 * 6. Continuous timeline with realistic visit & travel times
 * 7. Meal & rest break planning
 * 8. Smart fuel range calculation and stop insertion
 * 9. Toll estimation
 * 10. Multi-day partitioning
 * 11. Feasibility check & auto-pruning
 * 12. Structured JSON generation
 */
async function planItinerary(params = {}) {
  const {
    startLocation,
    destination,
    tripType = "around",
    startDate = "",
    startTime = "08:00",
    startDateTime = "",
    timezone = "Asia/Kolkata",
    durationDays = 1,
    mode = "balanced",
    places = [],
    selectedCategories = [],
    categoryPriorities = {},
    preferences = "",
    vehicle = {},
    travellers = 1,
    searchRadiusKm = 25,
  } = params;

  if (!destination) {
    throw new Error("We couldn't identify the selected destination. Please select the destination again.");
  }

  // Step 1 & 2: Pre-Flight Destination Validation & Hard Locking (Requirements #1, #2, #3, #9, #12)
  const destPt = await resolveLocation(destination, "Trip Destination");
  if (!destPt || !Number.isFinite(destPt.lat) || !Number.isFinite(destPt.lng) || (destPt.lat === 0 && destPt.lng === 0)) {
    throw new Error("We couldn't identify the selected destination. Please select the destination again.");
  }

  const startPt = await resolveLocation(startLocation || destPt, "Trip Origin");
  if (!startPt || !Number.isFinite(startPt.lat) || !Number.isFinite(startPt.lng) || (startPt.lat === 0 && startPt.lng === 0)) {
    throw new Error("We couldn't identify the starting location. Please select the starting point again.");
  }

  // Hard Destination Lock (Requirements #3 & #12)
  const lockedDestination = Object.freeze({
    name: destPt.name,
    lat: destPt.lat,
    lng: destPt.lng,
    latitude: destPt.lat,
    longitude: destPt.lng,
    placeId: destPt.placeId || `dest_${destPt.name.toLowerCase().replace(/[^a-z0-9]/g, '_')}_${Math.round(destPt.lat * 1000)}_${Math.round(destPt.lng * 1000)}`,
    address: destPt.address || destPt.name,
    city: destPt.city || destPt.name,
    state: destPt.state || "",
    country: destPt.country || "India",
    type: "destination",
    locked: true,
    userSelected: true,
  });

  const isAroundTrip = String(tripType).toLowerCase() !== "one_way";
  const searchRadius = Math.max(5, Math.min(Number(searchRadiusKm) || 25, 100));
  const totalDays = Math.max(1, Math.min(Number(durationDays) || 1, 14));
  const startMinutes = parseMinutes(startTime);

  // Step 3: Pre-Route Corridor Calculation (Requirement #5)
  const baseCorridorRoute = await routeBetweenPoints(startPt, lockedDestination);
  const directDist = haversineDistanceKm(startPt, lockedDestination);
  const maxCorridorDetourKm = Math.min(25, Math.max(8, directDist * 0.15));

  // Diagnostic Logging (Requirement #24)
  console.log(`[SMART PLANNER] ==========================================`);
  console.log(`[SMART PLANNER] USER DESTINATION:        ${lockedDestination.name}`);
  console.log(`[SMART PLANNER] DESTINATION PLACE ID:    ${lockedDestination.placeId}`);
  console.log(`[SMART PLANNER] ORIGIN:                  ${startPt.name}`);
  console.log(`[SMART PLANNER] DIRECT DISTANCE:         ${directDist.toFixed(1)} km`);
  console.log(`[SMART PLANNER] BASELINE ROAD DISTANCE:  ${baseCorridorRoute.distanceKm.toFixed(1)} km`);
  console.log(`[SMART PLANNER] TRIP TYPE:               ${isAroundTrip ? 'Around / Round Trip' : 'One-Way'}`);

  // Step 4: Discover Candidate Places & Filter Against Route Corridor (Requirement #6 & #7)
  const rawCandidates = [];
  const isLocalTrip = directDist <= 30;

  // A. User-specified places take top priority
  for (const p of places) {
    if (!p) continue;
    const resolved = await resolveLocation(p, String(p), lockedDestination);
    if (resolved) {
      rawCandidates.push({
        ...resolved,
        placeId: resolved.placeId || `user_${Math.round(resolved.lat * 10000)}_${Math.round(resolved.lng * 10000)}`,
        isUserSpecified: true,
        category: resolved.category || "famous_places",
        source: "user_specified",
      });
    }
  }

  // B. Curated database matching strictly near destination or along practical corridor
  for (const cp of curatedPlaces) {
    const distToDest = haversineDistanceKm(lockedDestination, cp);
    const distToStart = haversineDistanceKm(startPt, cp);
    const isNearDest = distToDest <= searchRadius;
    const isNearStart = isLocalTrip && distToStart <= searchRadius;
    const corridorDetour = distToStart + distToDest - directDist;
    const isAlongCorridor =
      !isLocalTrip &&
      directDist > 50 &&
      distToStart > 30 &&
      distToDest > searchRadius &&
      distToStart <= directDist * 1.05 &&
      distToDest <= directDist * 1.05 &&
      corridorDetour <= maxCorridorDetourKm;

    if (isNearDest || isNearStart || isAlongCorridor) {
      rawCandidates.push({
        ...cp,
        address: `${cp.name}, ${cp.city}, ${cp.state}`,
        isUserSpecified: false,
        source: "curated",
      });
    }
  }

  // C. Dynamic live POI search strictly around locked destination
  try {
    const photonCats = selectedCategories.length > 0
      ? selectedCategories.map((c) => c.toLowerCase().trim().replace(/[^a-z0-9]/g, "_"))
      : ["temple", "attraction", "viewpoint"];
    const osmPlaces = await findPOIsInArea(lockedDestination, photonCats, searchRadius);
    for (const op of osmPlaces) {
      rawCandidates.push(op);
    }
  } catch (err) {
    console.warn("Photon live POI discovery skipped:", err.message);
  }

  // Step 4: Filter & Score candidates against category & corridor detour
  const filteredPlaces = filterAndScoreCandidates({
    candidates: rawCandidates,
    selectedCategories,
    categoryPriorities,
    baseAxisStart: startPt,
    baseAxisEnd: lockedDestination,
    searchRadiusKm: searchRadius,
  });

  const candidateMap = new Map(filteredPlaces.map((c) => [c.placeId, c]));

  // Limit stops per day based on pace and duration
  const stopsPerDay = mode === "packed" ? 5 : mode === "relaxed" ? 3 : 4;
  const maxStops = Math.max(1, Math.min(filteredPlaces.length, totalDays * stopsPerDay));

  // AI selection & ranking from strictly validated candidates only
  let candidateStops = [];
  try {
    const aiStops = await rankCandidatesWithAI({
      candidates: filteredPlaces,
      destination: lockedDestination,
      origin: startPt,
      maxStops,
      preferences,
    });
    for (const s of aiStops) {
      const match = candidateMap.get(s.placeId);
      if (match && !candidateStops.some((existing) => existing.placeId === match.placeId)) {
        candidateStops.push(match);
      }
    }
  } catch (_) {}

  // Complete with top-ranked candidates if needed
  if (candidateStops.length === 0) {
    candidateStops = filteredPlaces.slice(0, maxStops);
  } else if (candidateStops.length < maxStops) {
    for (const p of filteredPlaces) {
      if (candidateStops.length >= maxStops) break;
      if (!candidateStops.some((s) => s.placeId === p.placeId)) {
        candidateStops.push(p);
      }
    }
  }

  // Hard stop validation: Drop any stop that fails geographic bounds or candidateMap
  candidateStops = candidateStops.filter((stop) => {
    if (!stop.placeId || !candidateMap.has(stop.placeId)) return false;
    if (!Number.isFinite(stop.lat) || !Number.isFinite(stop.lng) || stop.lat === 0) return false;
    const distToDest = haversineDistanceKm(lockedDestination, stop);
    const distToStart = haversineDistanceKm(startPt, stop);
    const corridorDetour = distToStart + distToDest - directDist;
    const inDestRadius = distToDest <= searchRadius;
    const inLocalRadius = isLocalTrip && distToStart <= searchRadius;
    const inCorridor = !isLocalTrip && distToStart > 25 && distToDest > searchRadius && corridorDetour <= maxCorridorDetourKm;
    return inDestRadius || inLocalRadius || inCorridor || stop.isUserSpecified;
  });

  // Step 5: Stop Partitioning (Transit Corridor vs Destination Area)
  // Ensures destination arrival happens on Day 1
  const midwayOutboundStops = [];
  const destAreaStops = [];

  for (const s of candidateStops) {
    const dDest = haversineDistanceKm(lockedDestination, s);
    if (dDest <= searchRadius || isLocalTrip) {
      destAreaStops.push(s);
    } else {
      midwayOutboundStops.push(s);
    }
  }

  // Sort midway outbound stops by increasing distance from start
  midwayOutboundStops.sort((a, b) => haversineDistanceKm(startPt, a) - haversineDistanceKm(startPt, b));

  // Optimize destination area stops to minimize local travel
  const optimizedDestStops = optimizeStopSequence({
    start: lockedDestination,
    end: lockedDestination,
    stops: destAreaStops,
    isAroundTrip: true,
  });

  // Step 6: Road Routing & Timeline Scheduling
  const efficiency = Number(vehicle.efficiencyKmPerLiter) > 0 ? Number(vehicle.efficiencyKmPerLiter) : (vehicle.type === "bike" ? 35 : 15);
  const tankCapacity = Number(vehicle.tankCapacityLiters) > 0 ? Number(vehicle.tankCapacityLiters) : (vehicle.type === "bike" ? 13 : 45);
  const currentFuel = Number(vehicle.currentFuelLiters) > 0 ? Number(vehicle.currentFuelLiters) : tankCapacity * 0.7;

  // Distribute destination sights across days
  // Day 1 gets outbound midway stops + Destination Arrival + some dest sights
  const dayBuckets = [];
  const remainingDestStops = [...optimizedDestStops];

  if (totalDays === 1) {
    dayBuckets.push([...midwayOutboundStops, ...remainingDestStops]);
  } else {
    // Multi-day trip: Day 1 takes all midway outbound stops + up to 2 initial dest sights
    const day1DestSights = remainingDestStops.splice(0, Math.min(2, Math.ceil(remainingDestStops.length / totalDays)));
    dayBuckets.push([...midwayOutboundStops, ...day1DestSights]);

    // Subsequent days share remaining destination sights
    const daysRemaining = totalDays - 1;
    const perDay = Math.ceil(remainingDestStops.length / daysRemaining) || 1;
    for (let d = 1; d < totalDays; d++) {
      dayBuckets.push(remainingDestStops.splice(0, perDay));
    }
  }

  const generatedDays = [];
  let cumulativeTripKm = 0;
  let remainingFuelLiters = currentFuel;
  let lastDayEndLocation = startPt;

  for (let dIdx = 0; dIdx < totalDays; dIdx++) {
    const dayNumber = dIdx + 1;
    const isFirstDay = dayNumber === 1;
    const isLastDay = dayNumber === totalDays;
    const dayStops = dayBuckets[dIdx] || [];

    let currentMin = isFirstDay ? startMinutes : 510; // Day 1: User start time; Subsequent: 08:30 AM
    const blocks = [];
    let prevLoc = isFirstDay ? startPt : lastDayEndLocation;

    // Starting block
    blocks.push({
      id: `d${dayNumber}_b0`,
      day: dayNumber,
      sequence: 0,
      type: "start",
      title: isFirstDay ? `Start from ${startPt.name}` : `Depart ${prevLoc.name}`,
      place: prevLoc.name,
      lat: prevLoc.lat,
      lng: prevLoc.lng,
      address: prevLoc.address || prevLoc.name,
      city: prevLoc.city || "",
      state: prevLoc.state || "",
      country: prevLoc.country || "India",
      start: formatMinutes(currentMin),
      end: formatMinutes(currentMin),
      durationMin: 0,
      travelMin: 0,
      distanceKm: 0,
      reason: isFirstDay ? "Trip departure" : "Resuming journey",
    });

    let lunchAdded = false;
    let teaAdded = false;
    let dinnerAdded = false;
    let destArrivalAdded = !isFirstDay; // Already at destination for Day 2+

    // Route through stops of the day
    for (let sIdx = 0; sIdx < dayStops.length; sIdx++) {
      const stop = dayStops[sIdx];
      const isStopInDestArea = haversineDistanceKm(lockedDestination, stop) <= searchRadius;

      // On Day 1, if transitioning from midway to destination area, insert Destination Arrival Block
      if (isFirstDay && !destArrivalAdded && isStopInDestArea) {
        const destLeg = await routeBetweenPoints(prevLoc, lockedDestination);
        blocks.push({
          id: `d1_travel_to_dest`,
          day: 1,
          sequence: blocks.length,
          type: "travel",
          title: `Drive to Destination: ${lockedDestination.name}`,
          place: lockedDestination.name,
          travelMode: "drive",
          lat: lockedDestination.lat,
          lng: lockedDestination.lng,
          start: formatMinutes(currentMin),
          end: formatMinutes(currentMin + destLeg.travelMin),
          durationMin: 0,
          travelMin: destLeg.travelMin,
          distanceKm: destLeg.distanceKm,
          reason: `Road journey to primary destination (${destLeg.distanceKm} km)`,
        });
        currentMin += destLeg.travelMin;
        cumulativeTripKm += destLeg.distanceKm;

        blocks.push({
          id: `d1_dest_arrival`,
          day: 1,
          sequence: blocks.length,
          type: "destination",
          title: `Arrive at Destination: ${lockedDestination.name}`,
          place: lockedDestination.name,
          category: "destination",
          lat: lockedDestination.lat,
          lng: lockedDestination.lng,
          latitude: lockedDestination.lat,
          longitude: lockedDestination.lng,
          address: lockedDestination.address || lockedDestination.name,
          city: lockedDestination.city || "",
          state: lockedDestination.state || "",
          country: lockedDestination.country || "India",
          start: formatMinutes(currentMin),
          end: formatMinutes(currentMin + 30),
          durationMin: 30,
          travelMin: 0,
          distanceKm: 0,
          placeId: lockedDestination.placeId,
          isDestination: true,
          isLocked: true,
          userSelected: true,
          reason: `Primary travel destination (${lockedDestination.name})`,
        });
        currentMin += 30;
        prevLoc = lockedDestination;
        destArrivalAdded = true;
      }

      const leg = await routeBetweenPoints(prevLoc, stop);
      const fuelNeeded = leg.distanceKm / efficiency;
      if (remainingFuelLiters < fuelNeeded + 3 && leg.distanceKm > 15) {
        const refuelLiters = Math.round((tankCapacity - remainingFuelLiters) * 10) / 10;
        blocks.push({
          id: `d${dayNumber}_fuel_${sIdx}`,
          day: dayNumber,
          sequence: blocks.length,
          type: "fuel",
          title: "Refuel at Highway Fuel Station",
          place: "Fuel Station",
          category: "fuel",
          lat: (prevLoc.lat + stop.lat) / 2,
          lng: (prevLoc.lng + stop.lng) / 2,
          address: "Highway Fuel Station",
          start: formatMinutes(currentMin),
          end: formatMinutes(currentMin + 15),
          durationMin: 15,
          travelMin: 0,
          distanceKm: 0,
          reason: `Low fuel reserve (${remainingFuelLiters.toFixed(1)}L). Refilled ${refuelLiters}L.`,
          isFuelStop: true,
        });
        currentMin += 15;
        remainingFuelLiters = tankCapacity;
      }

      // Travel Block
      const travelStart = currentMin;
      const travelEnd = currentMin + leg.travelMin;
      blocks.push({
        id: `d${dayNumber}_travel_${sIdx}`,
        day: dayNumber,
        sequence: blocks.length,
        type: "travel",
        title: `Drive to ${stop.name}`,
        place: stop.name,
        travelMode: "drive",
        lat: stop.lat,
        lng: stop.lng,
        start: formatMinutes(travelStart),
        end: formatMinutes(travelEnd),
        durationMin: 0,
        travelMin: leg.travelMin,
        distanceKm: leg.distanceKm,
        reason: `Road travel (${leg.distanceKm} km)`,
      });
      currentMin = travelEnd;
      cumulativeTripKm += leg.distanceKm;
      remainingFuelLiters = Math.max(0, remainingFuelLiters - fuelNeeded);

      // Lunch window: 12:30 PM (750m) - 1:45 PM (825m)
      if (!lunchAdded && currentMin >= 750 && currentMin <= 850) {
        blocks.push({
          id: `d${dayNumber}_meal_lunch`,
          day: dayNumber,
          sequence: blocks.length,
          type: "meal",
          breakType: "lunch",
          title: "Lunch Break",
          place: `Restaurant near ${stop.name}`,
          category: "restaurant",
          lat: stop.lat,
          lng: stop.lng,
          start: formatMinutes(currentMin),
          end: formatMinutes(currentMin + 50),
          durationMin: 50,
          travelMin: 0,
          distanceKm: 0,
          reason: "Midday meal and refreshment",
        });
        currentMin += 50;
        lunchAdded = true;
      }

      // Activity Block
      const visitDur = stop.visitDurationMin || CATEGORY_DURATIONS[stop.category] || CATEGORY_DURATIONS.default;
      const actStart = currentMin;
      const actEnd = currentMin + visitDur;
      blocks.push({
        id: `d${dayNumber}_stop_${sIdx}`,
        placeId: stop.placeId,
        day: dayNumber,
        sequence: blocks.length,
        type: "activity",
        title: `Visit ${stop.name}`,
        place: stop.name,
        category: stop.category || "attraction",
        categories: stop.categories || [stop.category || "attraction"],
        lat: stop.lat,
        lng: stop.lng,
        latitude: stop.lat,
        longitude: stop.lng,
        destinationDistanceKm: stop.destinationDistanceKm,
        address: stop.address || stop.name,
        city: stop.city || "",
        state: stop.state || "",
        country: stop.country || "India",
        start: formatMinutes(actStart),
        end: formatMinutes(actEnd),
        durationMin: visitDur,
        travelMin: 0,
        distanceKm: 0,
        openingHours: stop.openingHours || "Open standard hours",
        whyIncluded: `Attraction in ${lockedDestination.name} area.`,
        reason: stop.description || "Sightseeing and exploration",
      });
      currentMin = actEnd;
      prevLoc = stop;

      // Tea break window: 4:45 PM (1005m) - 5:30 PM (1050m)
      if (!teaAdded && currentMin >= 1005 && currentMin <= 1065) {
        blocks.push({
          id: `d${dayNumber}_tea`,
          day: dayNumber,
          sequence: blocks.length,
          type: "coffee",
          breakType: "tea",
          title: "Tea & Refreshment Break",
          place: `Café near ${stop.name}`,
          category: "restaurant",
          lat: stop.lat,
          lng: stop.lng,
          start: formatMinutes(currentMin),
          end: formatMinutes(currentMin + 25),
          durationMin: 25,
          travelMin: 0,
          distanceKm: 0,
          reason: "Rest break and tea/coffee",
        });
        currentMin += 25;
        teaAdded = true;
      }

      if (currentMin >= 1260 && sIdx < dayStops.length - 1) break;
    }

    // If Day 1 had no midway stops, ensure Destination Arrival Block is explicitly added
    if (isFirstDay && !destArrivalAdded) {
      blocks.push({
        id: `d1_dest_arrival`,
        day: 1,
        sequence: blocks.length,
        type: "destination",
        title: `Arrive at Destination: ${lockedDestination.name}`,
        place: lockedDestination.name,
        category: "destination",
        lat: lockedDestination.lat,
        lng: lockedDestination.lng,
        latitude: lockedDestination.lat,
        longitude: lockedDestination.lng,
        address: lockedDestination.address || lockedDestination.name,
        city: lockedDestination.city || "",
        state: lockedDestination.state || "",
        country: lockedDestination.country || "India",
        start: formatMinutes(currentMin),
        end: formatMinutes(currentMin + 30),
        durationMin: 30,
        travelMin: 0,
        distanceKm: 0,
        placeId: lockedDestination.placeId,
        isDestination: true,
        isLocked: true,
        userSelected: true,
        reason: `Primary travel destination (${lockedDestination.name})`,
      });
      currentMin += 30;
      prevLoc = lockedDestination;
    }

    // Dinner Window
    if (!dinnerAdded && currentMin >= 1170) {
      blocks.push({
        id: `d${dayNumber}_meal_dinner`,
        day: dayNumber,
        sequence: blocks.length,
        type: "meal",
        breakType: "dinner",
        title: "Dinner",
        place: `Restaurant in ${lockedDestination.name}`,
        category: "restaurant",
        lat: prevLoc.lat,
        lng: prevLoc.lng,
        start: formatMinutes(currentMin),
        end: formatMinutes(currentMin + 55),
        durationMin: 55,
        travelMin: 0,
        distanceKm: 0,
        reason: `Evening dinner in ${lockedDestination.name}`,
      });
      currentMin += 55;
      dinnerAdded = true;
    }

    // Day conclusion: Final Return vs Overnight Stay vs One-Way Finish
    if (isLastDay) {
      if (isAroundTrip) {
        // Return Leg to Origin
        const returnLeg = await routeBetweenPoints(prevLoc, startPt);
        blocks.push({
          id: `d${dayNumber}_final_return`,
          day: dayNumber,
          sequence: blocks.length,
          type: "return",
          title: `Return to Origin (${startPt.name})`,
          place: startPt.name,
          travelMode: "drive",
          lat: startPt.lat,
          lng: startPt.lng,
          address: startPt.address || startPt.name,
          start: formatMinutes(currentMin),
          end: formatMinutes(currentMin + returnLeg.travelMin),
          durationMin: 0,
          travelMin: returnLeg.travelMin,
          distanceKm: returnLeg.distanceKm,
          reason: `Return journey to origin (${returnLeg.distanceKm} km)`,
        });
        currentMin += returnLeg.travelMin;
        cumulativeTripKm += returnLeg.distanceKm;
      } else {
        // One-Way trip finishes at Destination
        blocks.push({
          id: `d${dayNumber}_final_completion`,
          day: dayNumber,
          sequence: blocks.length,
          type: "destination",
          title: `Trip Completed at ${lockedDestination.name}`,
          place: lockedDestination.name,
          lat: lockedDestination.lat,
          lng: lockedDestination.lng,
          address: lockedDestination.address || lockedDestination.name,
          start: formatMinutes(currentMin),
          end: formatMinutes(currentMin),
          durationMin: 0,
          travelMin: 0,
          distanceKm: 0,
          isDestination: true,
          isLocked: true,
          reason: `Journey successfully completed at ${lockedDestination.name}`,
        });
      }
    } else {
      // Overnight stay at Destination
      const hotel = typeof getBestCuratedVenue === "function" ? getBestCuratedVenue(lockedDestination.name, "hotel") : null;
      const hotelName = hotel && hotel.name ? hotel.name : `Comfort Stay in ${lockedDestination.name}`;
      const hotelAddress = hotel && hotel.city ? `${hotelName}, ${hotel.city}` : `Hotel in ${lockedDestination.name}`;

      blocks.push({
        id: `d${dayNumber}_hotel`,
        day: dayNumber,
        sequence: blocks.length,
        type: "checkin",
        title: `Overnight Stay: ${hotelName}`,
        place: hotelName,
        category: "hotel",
        lat: prevLoc.lat,
        lng: prevLoc.lng,
        latitude: prevLoc.lat,
        longitude: prevLoc.lng,
        address: hotelAddress,
        city: lockedDestination.city || lockedDestination.name,
        state: lockedDestination.state || "",
        country: lockedDestination.country || "India",
        start: formatMinutes(currentMin),
        end: formatMinutes(Math.min(currentMin + 60, 1439)),
        durationMin: 60,
        travelMin: 0,
        distanceKm: 0,
        reason: hotel && hotel.specialty ? `Night rest: ${hotel.specialty}` : `Night rest in ${lockedDestination.name} for Day ${dayNumber + 1}`,
      });
      lastDayEndLocation = prevLoc;
    }

    generatedDays.push({
      day: dayNumber,
      date: startDate || `Day ${dayNumber}`,
      title: `Day ${dayNumber}: ${isFirstDay ? `Travel to & Explore ${lockedDestination.name}` : isLastDay ? (isAroundTrip ? `Final Sights in ${lockedDestination.name} & Return` : `Explore ${lockedDestination.name}`) : `Full Day in ${lockedDestination.name}`}`,
      blocks,
    });
  }

  // Step 6.5: Authoritative Multi-Stop Road Routing & Strict Budget
  let authoritativeRouteResult = null;
  try {
    const extractedStops = [];
    for (const d of generatedDays) {
      for (const b of d.blocks) {
        if (
          b.lat && b.lng &&
          (b.type === "activity" || b.type === "fuel" || b.type === "attraction") &&
          !b.isDestination
        ) {
          const isDup = extractedStops.some((prev) => haversineDistanceKm(prev, b) < 0.1);
          if (!isDup) {
            extractedStops.push({
              id: b.id,
              name: b.place || b.title,
              lat: b.lat,
              lng: b.lng,
              address: b.address || b.place || b.title,
              type: b.type,
              sequence: extractedStops.length + 1,
              durationMin: b.durationMin,
              stayDuration: b.durationMin,
              category: b.category,
              reason: b.reason,
            });
          }
        }
      }
    }

    authoritativeRouteResult = await calculateTripRoute({
      origin: startPt,
      destination: lockedDestination,
      stops: extractedStops,
      vehicle: {
        type: vehicle.type || "car",
        efficiencyKmPerLiter: efficiency,
        tankCapacityLiters: tankCapacity,
        currentFuelLiters: currentFuel,
      },
      tripType: isAroundTrip ? "around" : "one_way",
      durationDays: totalDays,
      travellers: Math.max(1, Number(vehicle.travellers) || 1),
      routeVersion: 1,
    });

    if (authoritativeRouteResult && authoritativeRouteResult.route) {
      cumulativeTripKm = authoritativeRouteResult.route.distanceKm;

      const legs = authoritativeRouteResult.route.legs || [];
      if (legs.length > 0) {
        let legIdx = 0;
        for (const d of generatedDays) {
          for (const b of d.blocks) {
            if ((b.type === "travel" || b.type === "return") && legIdx < legs.length) {
              const rLeg = legs[legIdx++];
              if (rLeg.distanceKm > 0) {
                b.distanceKm = Math.round(rLeg.distanceKm * 10) / 10;
                b.travelMin = Math.max(1, Math.round(rLeg.durationMin || (rLeg.durationSeconds / 60) || 5));
              }
            }
          }
        }
      }
    }

    console.log(`[SMART PLANNER] GENERATED STOPS:         ${extractedStops.length} stop(s)`);
    console.log(`[SMART PLANNER] FINAL ROUTE DESTINATION: ${lockedDestination.name} (${lockedDestination.lat}, ${lockedDestination.lng})`);
    console.log(`[SMART PLANNER] FINAL NAVIGATION DEST:   ${lockedDestination.name}`);
    console.log(`[SMART PLANNER] ==========================================`);
  } catch (err) {
    console.warn("[ITINERARY ENGINE] Authoritative route calculation fallback:", err.message);
  }

  // Step 7: Automated Quality Gate Verification (Requirement #27)
  validateItineraryQuality({
    days: generatedDays,
    startLocation: startPt,
    destination: lockedDestination,
    isAroundTrip,
    startMinutes,
    candidateMap,
    searchRadiusKm: searchRadius,
    selectedCategories,
  });

  return {
    days: generatedDays,
    tripType: isAroundTrip ? "around" : "one_way",
    startPoint: startPt,
    endPoint: isAroundTrip ? startPt : lockedDestination,
    destinationPoint: lockedDestination,
    searchRadiusKm: searchRadius,
    placesFoundCount: candidateStops.length,
    canExpandSearch: searchRadius < 100,
    nextSearchRadiusKm: searchRadius < 50 ? 50 : 100,
    totalDistanceKm: authoritativeRouteResult ? authoritativeRouteResult.route.distanceKm : Math.round(cumulativeTripKm * 10) / 10,
    totalDurationMin: authoritativeRouteResult ? authoritativeRouteResult.route.durationMin : generatedDays.reduce((acc, d) => {
      const first = parseMinutes(d.blocks[0]?.start);
      const last = parseMinutes(d.blocks[d.blocks.length - 1]?.end);
      return acc + (last >= first ? last - first : 1440 - first + last);
    }, 0),
    route: authoritativeRouteResult?.route || null,
    navigationRoute: authoritativeRouteResult?.navigationRoute || null,
    tripPlan: authoritativeRouteResult?.tripPlan || null,
    routeVersion: authoritativeRouteResult?.routeVersion || 1,
    budget: authoritativeRouteResult?.budget || null,
    isConfirmed: false,
    status: "DRAFT",
  };
}

/**
 * 17-Point Automated Itinerary Quality Gate
 */
function validateItineraryQuality({
  days,
  startLocation,
  destination,
  isAroundTrip,
  startMinutes,
  candidateMap,
  searchRadiusKm = 25,
  selectedCategories = [],
}) {
  if (!Array.isArray(days) || days.length === 0) {
    throw new Error("Quality Gate Failed: No days produced");
  }

  // Guarantee NO [object Object] anywhere in locations or blocks
  if (destination.name && destination.name.includes("[object Object]")) {
    throw new Error("Quality Gate Failed: Destination name contains [object Object]");
  }
  if (startLocation.name && startLocation.name.includes("[object Object]")) {
    throw new Error("Quality Gate Failed: Start location name contains [object Object]");
  }

  const day1 = days[0];
  if (!day1.blocks || day1.blocks.length < 2) {
    throw new Error("Quality Gate Failed: Day 1 has insufficient timeline blocks");
  }

  // Check Day 1 Start Time
  const firstBlock = day1.blocks[0];
  const actualStartMin = parseMinutes(firstBlock.start);
  if (Math.abs(actualStartMin - startMinutes) > 10) {
    throw new Error(`Quality Gate Failed: Start time mismatch. Expected ${formatMinutes(startMinutes)}, got ${firstBlock.start}`);
  }

  // Check Destination Arrival on Day 1
  const day1DestArrival = day1.blocks.find((b) => b.isDestination === true || b.id === "d1_dest_arrival");
  if (!day1DestArrival) {
    throw new Error(`Quality Gate Failed: Day 1 does not contain arrival at destination (${destination.name}).`);
  }

  // Check End Location based on Trip Type
  const lastDay = days[days.length - 1];
  const lastBlock = lastDay.blocks[lastDay.blocks.length - 1];
  if (isAroundTrip) {
    if (haversineDistanceKm(lastBlock, startLocation) > 5) {
      throw new Error("Quality Gate Failed: Around Trip did not return to start location origin.");
    }
  } else {
    // One-Way Trip must terminate at the destination
    if (!lastBlock.isDestination && haversineDistanceKm(lastBlock, destination) > 5) {
      throw new Error(`Quality Gate Failed: One-Way Trip did not end at destination (${destination.name}).`);
    }
  }

  const directDist = haversineDistanceKm(startLocation, destination);
  const isLocalTrip = directDist <= 30;

  // Forbidden cities check if destination is Tirumala or nearby
  const destLower = (destination.name || "").toLowerCase();
  const isTirumalaDest = destLower.includes("tirumala");
  const forbiddenTirumalaKeywords = ["chennai", "pondicherry", "mysore", "mysuru", "hyderabad", "madurai", "coimbatore", "kodaikanal", "ooty"];

  // Check Non-overlapping and sequential timeline & place validity
  for (const day of days) {
    if (day.title && day.title.includes("[object Object]")) {
      throw new Error(`Quality Gate Failed: Day ${day.day} title contains [object Object]`);
    }
    let prevEnd = -1;
    for (const b of day.blocks) {
      if (b.title && b.title.includes("[object Object]")) {
        throw new Error(`Quality Gate Failed: Block title "${b.title}" contains [object Object]`);
      }
      if (b.place && b.place.includes("[object Object]")) {
        throw new Error(`Quality Gate Failed: Block place "${b.place}" contains [object Object]`);
      }

      const bStart = parseMinutes(b.start);
      const bEnd = parseMinutes(b.end);
      if (prevEnd !== -1 && bStart < prevEnd - 1) {
        throw new Error(`Quality Gate Failed: Overlapping timeline in Day ${day.day} at ${b.title}`);
      }
      prevEnd = bEnd;

      // Coordinate check
      if (b.type === "activity" || b.type === "start" || b.type === "return" || b.type === "destination") {
        if (!Number.isFinite(b.lat) || !Number.isFinite(b.lng) || b.lat === 0) {
          throw new Error(`Quality Gate Failed: Missing coordinates for block ${b.title}`);
        }
      }

      // Check forbidden distant cities
      if (isTirumalaDest && (b.type === "activity" || b.type === "travel")) {
        const placeStr = `${b.title} ${b.place || ""} ${b.address || ""} ${b.city || ""}`.toLowerCase();
        for (const kw of forbiddenTirumalaKeywords) {
          if (placeStr.includes(kw) && !destLower.includes(kw)) {
            throw new Error(`Quality Gate Failed: Block "${b.title}" contains forbidden city "${kw}" unrelated to ${destination.name}.`);
          }
        }
      }

      // Hard Validation Check for activity blocks
      if (b.type === "activity") {
        if (!b.placeId) {
          throw new Error(`Quality Gate Failed: Missing placeId for block "${b.title}"`);
        }
        if (candidateMap && !candidateMap.has(b.placeId)) {
          throw new Error(`Quality Gate Failed: Unrecognized placeId "${b.placeId}" for block "${b.title}"`);
        }
        // Geographic constraint check
        const distToDest = haversineDistanceKm(destination, b);
        const distToStart = haversineDistanceKm(startLocation, b);
        const corridorDetour = distToStart + distToDest - directDist;
        const inDestRadius = distToDest <= searchRadiusKm;
        const inLocalRadius = isLocalTrip && distToStart <= searchRadiusKm;
        const inCorridor = !isLocalTrip && distToStart > 30 && distToDest > searchRadiusKm && corridorDetour <= 20;

        if (!inDestRadius && !inLocalRadius && !inCorridor && !b.isDestinationAnchor && !b.isUserSpecified) {
          throw new Error(
            `Quality Gate Failed: Block "${b.title}" is outside destination and route bounds (distToDest: ${distToDest.toFixed(1)}km, searchRadius: ${searchRadiusKm}km).`
          );
        }
      }
    }
  }

  return true;
}

module.exports = {
  planItinerary,
  parseMinutes,
  formatMinutes,
  format24h,
  optimizeStopSequence,
  filterAndScoreCandidates,
  routeBetweenPoints,
  resolveLocation,
  extractLocationName,
  normalizeCanonicalLocation,
  validateItineraryQuality,
  CATEGORY_DURATIONS,
};
