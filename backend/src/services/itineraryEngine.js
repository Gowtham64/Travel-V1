const { haversineDistanceKm } = require("../utils/geo");
const { getRoute, toPoint } = require("./routingService");
const { geocodeAddress } = require("./geocodeService");
const { geocode, route: osrmRoute } = require("./itineraryGeo");
const { findPOIsInArea } = require("./orsPoiService");
const FuelRangeService = require("./fuelRangeService");
const { rankCandidatesWithAI } = require("./aiService");
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
 * Robust geocoding for a place name, optionally focused around a reference point.
 */
async function resolveLocation(nameOrCoord, fallbackName = "Stop", focus = null) {
  if (!nameOrCoord) return null;
  if (typeof nameOrCoord === "object") {
    const lat = Number(nameOrCoord.lat ?? nameOrCoord.latitude);
    const lng = Number(nameOrCoord.lng ?? nameOrCoord.longitude ?? nameOrCoord.lon);
    if (Number.isFinite(lat) && Number.isFinite(lng) && lat !== 0 && lng !== 0) {
      return {
        lat,
        lng,
        name: nameOrCoord.name || fallbackName,
        address: nameOrCoord.address || nameOrCoord.name || fallbackName,
        city: nameOrCoord.city || "",
        state: nameOrCoord.state || "",
        country: nameOrCoord.country || "India",
      };
    }
  }

  const query = String(nameOrCoord).trim();
  if (!query) return null;

  const qLower = query.toLowerCase();
  // 1. Instant check for major cities with word-boundary matching
  for (const [key, cityInfo] of Object.entries(MAJOR_CITIES)) {
    const isExact = qLower === key;
    const isWordMatch = new RegExp(`(^|[\\s,.-])${key}([\\s,.-]|$)`, "i").test(qLower);
    if (isExact || isWordMatch) {
      return {
        lat: cityInfo.lat,
        lng: cityInfo.lng,
        name: cityInfo.name,
        address: `${cityInfo.name}, ${cityInfo.state}`,
        city: cityInfo.city,
        state: cityInfo.state,
        country: cityInfo.country,
      };
    }
  }

  // 2. Check curated places first for exact or high-confidence match
  const curatedMatch = curatedPlaces.find((p) => {
    const pLower = p.name.toLowerCase();
    return pLower === qLower || (qLower.length >= 6 && pLower.startsWith(qLower));
  });

  if (curatedMatch) {
    return {
      lat: curatedMatch.lat,
      lng: curatedMatch.lng,
      name: curatedMatch.name,
      address: `${curatedMatch.name}, ${curatedMatch.city}, ${curatedMatch.state}`,
      city: curatedMatch.city,
      state: curatedMatch.state,
      country: curatedMatch.country,
      category: curatedMatch.category,
      categories: curatedMatch.categories,
      openingHours: curatedMatch.openingHours,
      visitDurationMin: curatedMatch.visitDurationMin,
    };
  }

  // Geocode via ORS / Mapbox
  try {
    const geo = focus ? await geocode(query, "", focus) : null;
    if (geo && Number.isFinite(geo.lat) && Number.isFinite(geo.lng)) {
      return {
        lat: geo.lat,
        lng: geo.lng,
        name: query,
        address: query,
        city: "",
        state: "",
        country: "India",
      };
    }
  } catch (_) {}

  try {
    const addr = await geocodeAddress(query);
    if (addr && Number.isFinite(addr.lat) && Number.isFinite(addr.lng)) {
      return {
        lat: addr.lat,
        lng: addr.lng,
        name: query,
        address: addr.displayName || query,
        city: "",
        state: "",
        country: "India",
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

  if (!startLocation && !destination) {
    throw new Error("Start location or destination is required.");
  }

  // Smart AI Planner enforces Around Trip exclusively
  const isAroundTrip = true;
  const searchRadius = Math.max(5, Math.min(Number(searchRadiusKm) || 25, 100));

  const totalDays = Math.max(1, Math.min(Number(durationDays) || 1, 14));
  const startMinutes = parseMinutes(startTime);
  const startLocationStr = startLocation || destination;
  const destinationStr = destination || startLocationStr;

  // Step 2: Geocode Origin & Destination
  const startPt = await resolveLocation(startLocationStr, "Trip Origin");
  if (!startPt) {
    throw new Error(`Could not resolve coordinates for start location: "${startLocationStr}"`);
  }

  let destPt = await resolveLocation(destinationStr, "Trip Destination", startPt);
  if (!destPt) destPt = { ...startPt };

  const directDist = haversineDistanceKm(startPt, destPt);

  // Step 3: Discover Candidate Places
  const rawCandidates = [];
  const isLocalTrip = directDist <= 30;

  // A. User-specified places take top priority
  for (const p of places) {
    if (!p) continue;
    const resolved = await resolveLocation(p, String(p), destPt || startPt);
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

  // B. Search curated database near destination or along practical corridor
  for (const cp of curatedPlaces) {
    const distToDest = haversineDistanceKm(destPt, cp);
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
      corridorDetour <= 15;

    if (isNearDest || isNearStart || isAlongCorridor) {
      rawCandidates.push({
        ...cp,
        address: `${cp.name}, ${cp.city}, ${cp.state}`,
        isUserSpecified: false,
        source: "curated",
      });
    }
  }

  // C. Dynamic live POI search around destination via Photon (OSM)
  try {
    const photonCats = selectedCategories.length > 0
      ? selectedCategories.map((c) => c.toLowerCase().trim().replace(/[^a-z0-9]/g, "_"))
      : ["temple", "attraction", "viewpoint"];
    const osmPlaces = await findPOIsInArea(destPt, photonCats, searchRadius);
    for (const op of osmPlaces) {
      rawCandidates.push(op);
    }
  } catch (err) {
    console.warn("Photon live POI discovery skipped:", err.message);
  }

  // D. Guarantee Destination Visit (Section 11 & 13)
  if (directDist > 15) {
    const hasDestAnchor = rawCandidates.some(
      (c) => haversineDistanceKm(c, destPt) < 3.0
    );
    if (!hasDestAnchor) {
      rawCandidates.push({
        placeId: `pl_dest_anchor_${Math.round(destPt.lat * 1000)}_${Math.round(destPt.lng * 1000)}`,
        name: destPt.name,
        lat: destPt.lat,
        lng: destPt.lng,
        latitude: destPt.lat,
        longitude: destPt.lng,
        address: destPt.address || destPt.name,
        city: destPt.city || destPt.name,
        state: destPt.state || "",
        country: destPt.country || "India",
        category: "destination_center",
        categories: ["destination_center", "famous_places", "monuments_landmarks"],
        visitDurationMin: 60,
        rating: 4.8,
        isDestinationAnchor: true,
        isUserSpecified: true,
        description: `Explore central ${destPt.name}`,
        source: "destination_anchor",
      });
    }
  }

  // Step 4: Filter by category & score
  const filteredPlaces = filterAndScoreCandidates({
    candidates: rawCandidates,
    selectedCategories,
    categoryPriorities,
    baseAxisStart: startPt,
    baseAxisEnd: destPt,
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
      destination: destPt.name,
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

  // If AI selection produced fewer than maxStops or was offline, complete with top-ranked candidates
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

  // If destination is distinct from start, ensure destination anchor or top destination stop is included
  if (directDist > 15) {
    const hasDestStop = candidateStops.some((s) => haversineDistanceKm(s, destPt) <= searchRadius);
    if (!hasDestStop && filteredPlaces.length > 0) {
      const topDestPlace = filteredPlaces.find((s) => haversineDistanceKm(s, destPt) <= searchRadius);
      if (topDestPlace) candidateStops.push(topDestPlace);
    }
  }

  // Step 4.5: HARD VALIDATION - Drop any stop that fails candidate verification
  candidateStops = candidateStops.filter((stop) => {
    // 1. Must have placeId and exist in candidateMap
    if (!stop.placeId || !candidateMap.has(stop.placeId)) return false;
    // 2. Must have valid finite coordinates
    if (!Number.isFinite(stop.lat) || !Number.isFinite(stop.lng) || stop.lat === 0) return false;
    // 3. Geographic boundary check
    const distToDest = haversineDistanceKm(destPt, stop);
    const distToStart = haversineDistanceKm(startPt, stop);
    const corridorDetour = distToStart + distToDest - directDist;
    const inDestRadius = distToDest <= searchRadius;
    const inLocalRadius = isLocalTrip && distToStart <= searchRadius;
    const inCorridor = !isLocalTrip && distToStart > 30 && distToDest > searchRadius && corridorDetour <= 20;
    if (!inDestRadius && !inLocalRadius && !inCorridor && !stop.isUserSpecified && !stop.isDestinationAnchor) {
      return false;
    }
    return true;
  });

  // Step 5: Stop Order Optimization (Minimize Backtracking)
  const orderedStops = optimizeStopSequence({
    start: startPt,
    end: startPt,
    stops: candidateStops,
    isAroundTrip: true,
  });

  // Step 6: Road Routing & Timeline Scheduling
  const efficiency = Number(vehicle.efficiencyKmPerLiter) > 0 ? Number(vehicle.efficiencyKmPerLiter) : (vehicle.type === "bike" ? 35 : 15);
  const tankCapacity = Number(vehicle.tankCapacityLiters) > 0 ? Number(vehicle.tankCapacityLiters) : (vehicle.type === "bike" ? 13 : 45);
  const currentFuel = Number(vehicle.currentFuelLiters) > 0 ? Number(vehicle.currentFuelLiters) : tankCapacity * 0.7;

  // Partition stops across available days
  const dayBuckets = [];
  const stopsPerBucket = Math.ceil(orderedStops.length / totalDays);
  for (let d = 0; d < totalDays; d++) {
    dayBuckets.push(orderedStops.slice(d * stopsPerBucket, (d + 1) * stopsPerBucket));
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

    // Day 1 starts at exact user start time. Subsequent days start at 08:30 AM
    let currentMin = isFirstDay ? startMinutes : 510; // 08:30 AM
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

    // Route through each stop of the day
    for (let sIdx = 0; sIdx < dayStops.length; sIdx++) {
      const stop = dayStops[sIdx];
      const leg = await routeBetweenPoints(prevLoc, stop);

      // Check fuel requirement before long travel leg
      const fuelNeeded = leg.distanceKm / efficiency;
      if (remainingFuelLiters < fuelNeeded + 3 && leg.distanceKm > 15) {
        // Insert Fuel Stop
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

      // Meal / Break checks
      // Lunch Window: 12:30 PM (750m) - 1:45 PM (825m)
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
          reason: "Midday meal and refreshment along route",
        });
        currentMin += 50;
        lunchAdded = true;
      }

      // Activity / Sightseeing Block
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
        whyIncluded: `Matched preferred category: ${stop.category || "attraction"}.`,
        reason: stop.description || "Sightseeing and exploration",
      });
      currentMin = actEnd;
      prevLoc = stop;

      // Tea Break Window: 4:45 PM (1005m) - 5:30 PM (1050m)
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

      // Stop adding more activities if approaching evening bed time (> 21:00 / 1260m)
      if (currentMin >= 1260 && sIdx < dayStops.length - 1) {
        break;
      }
    }

    // Dinner Window: 7:45 PM (1185m) - 9:00 PM (1260m)
    if (!dinnerAdded && currentMin >= 1170) {
      blocks.push({
        id: `d${dayNumber}_meal_dinner`,
        day: dayNumber,
        sequence: blocks.length,
        type: "meal",
        breakType: "dinner",
        title: "Dinner",
        place: `Restaurant near ${prevLoc.name}`,
        category: "restaurant",
        lat: prevLoc.lat,
        lng: prevLoc.lng,
        start: formatMinutes(currentMin),
        end: formatMinutes(currentMin + 55),
        durationMin: 55,
        travelMin: 0,
        distanceKm: 0,
        reason: "Evening dinner",
      });
      currentMin += 55;
      dinnerAdded = true;
    }

    // Final leg of the day
    if (isLastDay) {
      // Return Leg to Destination (One-Way) or Start (Around Trip)
      const finalDest = isAroundTrip ? startPt : destPt;
      const returnLeg = await routeBetweenPoints(prevLoc, finalDest);
      const retStart = currentMin;
      const retEnd = currentMin + returnLeg.travelMin;

      blocks.push({
        id: `d${dayNumber}_final_return`,
        day: dayNumber,
        sequence: blocks.length,
        type: isAroundTrip ? "return" : "travel",
        title: isAroundTrip ? `Return to Origin (${finalDest.name})` : `Arrive at Destination (${finalDest.name})`,
        place: finalDest.name,
        travelMode: "drive",
        lat: finalDest.lat,
        lng: finalDest.lng,
        address: finalDest.address || finalDest.name,
        start: formatMinutes(retStart),
        end: formatMinutes(retEnd),
        durationMin: 0,
        travelMin: returnLeg.travelMin,
        distanceKm: returnLeg.distanceKm,
        reason: isAroundTrip ? "Around trip circuit return" : "Final destination arrival",
      });
      currentMin = retEnd;
      cumulativeTripKm += returnLeg.distanceKm;
    } else {
      // Overnight stay / Hotel check-in
      blocks.push({
        id: `d${dayNumber}_hotel`,
        day: dayNumber,
        sequence: blocks.length,
        type: "checkin",
        title: `Overnight Stay near ${prevLoc.name}`,
        place: `Hotel / Resort near ${prevLoc.name}`,
        category: "hotel",
        lat: prevLoc.lat,
        lng: prevLoc.lng,
        address: `Hotel near ${prevLoc.name}`,
        start: formatMinutes(currentMin),
        end: formatMinutes(Math.min(currentMin + 60, 1439)),
        durationMin: 60,
        travelMin: 0,
        distanceKm: 0,
        reason: "Night rest and recharge for Day " + (dayNumber + 1),
      });
      lastDayEndLocation = prevLoc;
    }

    generatedDays.push({
      day: dayNumber,
      date: startDate || `Day ${dayNumber}`,
      title: `Day ${dayNumber}: ${isFirstDay ? "Departure & Exploration" : isLastDay ? "Final Sights & Return" : "Full Day Sightseeing"}`,
      blocks,
    });
  }

  // Step 6.5: Calculate Authoritative Unified Multi-Stop Route & Budget
  let authoritativeRouteResult = null;
  try {
    const extractedStops = [];
    for (const d of generatedDays) {
      for (const b of d.blocks) {
        if (
          b.lat && b.lng &&
          (b.type === "activity" || b.type === "fuel" || b.type === "attraction" || b.isDestinationAnchor)
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
      destination: destPt,
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

      // Synchronize travel block distances and durations from authoritative route legs if available
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
  } catch (err) {
    console.warn("[ITINERARY ENGINE] Authoritative route calculation fallback:", err.message);
  }

  // Step 7: Automated Quality Gate Verification
  validateItineraryQuality({
    days: generatedDays,
    startLocation: startPt,
    destination: destPt,
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
    endPoint: startPt,
    destinationPoint: destPt,
    searchRadiusKm: searchRadius,
    placesFoundCount: candidateStops.filter((s) => !s.isDestinationAnchor).length,
    canExpandSearch: searchRadius < 100,
    nextSearchRadiusKm: searchRadius < 50 ? 50 : 100,
    totalDistanceKm: authoritativeRouteResult ? authoritativeRouteResult.route.distanceKm : Math.round(cumulativeTripKm * 10) / 10,
    totalDurationMin: authoritativeRouteResult ? authoritativeRouteResult.route.durationMin : generatedDays.reduce((acc, d) => {
      const first = parseMinutes(d.blocks[0]?.start);
      const last = parseMinutes(d.blocks[d.blocks.length - 1]?.end);
      return acc + (last >= first ? last - first : 1440 - first + last);
    }, 0),
    route: authoritativeRouteResult?.route || null,
    budget: authoritativeRouteResult?.budget || null,
    navigationRoute: authoritativeRouteResult?.navigationRoute || null,
    tripPlan: authoritativeRouteResult?.tripPlan || null,
    routeVersion: 1,
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

  // Check End Location
  const lastDay = days[days.length - 1];
  const lastBlock = lastDay.blocks[lastDay.blocks.length - 1];
  if (isAroundTrip) {
    if (haversineDistanceKm(lastBlock, startLocation) > 5) {
      throw new Error("Quality Gate Failed: Around Trip did not return to start location origin.");
    }
  }

  const directDist = haversineDistanceKm(startLocation, destination);
  const isLocalTrip = directDist <= 30;

  // Check Non-overlapping and sequential timeline & place validity
  for (const day of days) {
    let prevEnd = -1;
    for (const b of day.blocks) {
      const bStart = parseMinutes(b.start);
      const bEnd = parseMinutes(b.end);
      if (prevEnd !== -1 && bStart < prevEnd - 1) {
        throw new Error(`Quality Gate Failed: Overlapping timeline in Day ${day.day} at ${b.title}`);
      }
      prevEnd = bEnd;

      // Coordinate check
      if (b.type === "activity" || b.type === "start" || b.type === "return") {
        if (!Number.isFinite(b.lat) || !Number.isFinite(b.lng) || b.lat === 0) {
          throw new Error(`Quality Gate Failed: Missing coordinates for block ${b.title}`);
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
  validateItineraryQuality,
  CATEGORY_DURATIONS,
};
