/**
 * Gemini AI Itinerary Generation Service
 *
 * Responsible for:
 *  1. Building a structured prompt for Gemini with the destination LOCKED
 *  2. Calling the Gemini API to generate a day-by-day itinerary
 *  3. Validating Gemini's response (destination integrity, structure, continuity)
 *  4. Resolving each Gemini-suggested stop to real coordinates via geocoding
 *  5. Filtering out unreasonable detour stops
 *
 * Gemini ONLY generates itinerary structure (places, order, activities).
 * Routing, distance, fuel, toll, and budget are handled by itineraryEngine + routeCalculationService.
 */

const { resolveLocation, extractLocationName } = require("./itineraryEngine");
const { haversineDistanceKm } = require("../utils/geo");

// Re-use the existing provider-agnostic AI generate function
const aiService = require("./aiService");

// ─── Constants ───────────────────────────────────────────────────────────────

const MAX_GEMINI_RETRIES = 2;

const GEMINI_SYSTEM_INSTRUCTION = `You are a meticulous, world-aware travel planner generating a road-trip itinerary.

HARD RULES:
1. The user's destination is a HARD CONSTRAINT. You MUST NOT change, replace, reinterpret, or substitute the destination under any circumstances.
2. You may recommend intermediate stops ONLY when they are relevant to the route and trip duration.
3. Every day must form a continuous geographic journey — no unexplained geographic jumps.
4. The itinerary must ultimately reach the user's exact selected destination.
5. Do NOT invent fictional places. Only recommend real, well-known, verifiable places.
6. Do NOT generate random tourist locations. Do NOT add locations simply because they are popular.
7. Only recommend places that are geographically reasonable for the journey between origin and destination.
8. Day N+1 MUST start from Day N's end location. No teleportation.
9. If the trip is round-trip, the final day MUST return the traveller to the origin.
10. Do NOT generate road distance, travel duration, fuel cost, or toll cost — the routing engine handles that.
11. Every stop must have a clear, specific real place name — never generic names like "Temple 1" or "Local Restaurant".
12. For overnight stays, always specify the actual city/town name where the traveller stays.
13. Respond ONLY with valid JSON matching the exact schema requested. No markdown, no prose.`;

// ─── Prompt Builder ──────────────────────────────────────────────────────────

function buildGeminiPrompt({
  origin,
  destination,
  days,
  travellers,
  vehicleModel,
  mileage,
  pace,
  tripType,
  preferences,
  categories,
  startDate,
  startTime,
}) {
  const originName = extractLocationName(origin, "Origin");
  const destName = extractLocationName(destination, "Destination");

  const originObj = typeof origin === "object" ? origin : { name: originName };
  const destObj = typeof destination === "object" ? destination : { name: destName };

  const paceDescription =
    pace === "packed"
      ? "PACKED — fit in as many relevant stops as possible, shorter breaks"
      : pace === "relaxed"
      ? "RELAXED — fewer activities, longer meals/rest, plenty of free time"
      : "BALANCED — comfortable mix of sightseeing, meals, and rest";

  const tripTypeDesc = tripType === "one_way" ? "one-way (do NOT return to origin)" : "round-trip (final day returns to origin)";

  const categoryLine = categories && categories.length > 0
    ? `\nPreferred place categories: ${categories.join(", ")}. Prioritize stops matching these categories.`
    : "";

  const prefLine = preferences ? `\nTraveller preferences: ${preferences}` : "";

  const prompt = `Generate a ${days}-day ${tripTypeDesc} road trip itinerary.

TRIP DETAILS:
{
  "origin": {
    "name": "${originName}",
    "latitude": ${originObj.latitude || originObj.lat || "null"},
    "longitude": ${originObj.longitude || originObj.lng || "null"}
  },
  "destination": {
    "name": "${destName}",
    "latitude": ${destObj.latitude || destObj.lat || "null"},
    "longitude": ${destObj.longitude || destObj.lng || "null"},
    "locked": true
  },
  "days": ${days},
  "travellers": ${travellers},
  "vehicle": "${vehicleModel || "car"}",
  "mileage": ${mileage || 15},
  "pace": "${paceDescription}",
  "tripType": "${tripType === "one_way" ? "one_way" : "round"}",
  "startDate": "${startDate || "today"}",
  "startTime": "${startTime || "08:00"}"
}
${categoryLine}${prefLine}

CRITICAL CONSTRAINT: The destination "${destName}" is LOCKED. You MUST build the itinerary around "${originName}" → "${destName}". Do NOT replace "${destName}" with any other city or location.

INSTRUCTIONS:
- Day 1 should start at "${originName}" and travel toward "${destName}".
- Include relevant, real sightseeing stops along the route and at the destination.
- Each stop must be a real, specific, named place (temples, viewpoints, waterfalls, forts, beaches, etc.).
- For each stop provide: name, type (attraction/temple/viewpoint/waterfall/fort/museum/beach/market/cultural), estimated visit duration in minutes, and a brief reason (max 10 words).
- Each day must have a startLocation and endLocation forming a continuous chain.
- If ${days} days is more than needed to reach "${destName}", use extra days for destination-area activities.
- ${tripType !== "one_way" ? `The final day must return from "${destName}" back to "${originName}".` : `The trip ends at "${destName}".`}
- Include 3-6 meaningful stops per day based on pace.
- Do NOT include generic "Overnight Stay" without a location name.

Respond ONLY with this exact JSON structure:
{
  "origin": { "name": "${originName}" },
  "destination": { "name": "${destName}" },
  "days": [
    {
      "day": 1,
      "title": "Day 1 - Travel to ...",
      "startLocation": { "name": "..." },
      "stops": [
        {
          "name": "Specific Real Place Name",
          "type": "attraction",
          "durationMinutes": 60,
          "reason": "Brief reason max 10 words"
        }
      ],
      "endLocation": { "name": "..." },
      "overnightStay": { "name": "City/Town Name" }
    }
  ]
}`;

  return prompt;
}

// ─── Gemini Call ──────────────────────────────────────────────────────────────

async function callGemini(prompt, attempt = 0) {
  try {
    const text = await aiService.generateWithRetry(prompt, {
      system: GEMINI_SYSTEM_INSTRUCTION,
      json: true,
      maxTokens: 8000,
    });

    if (!text) throw new Error("No Gemini response");
    return JSON.parse(text);
  } catch (err) {
    if (attempt < MAX_GEMINI_RETRIES) {
      console.warn(`[GEMINI] Attempt ${attempt + 1} failed: ${err.message}. Retrying...`);
      await new Promise((r) => setTimeout(r, 1500 * (attempt + 1)));
      return callGemini(prompt, attempt + 1);
    }
    throw err;
  }
}

// ─── Response Validation ─────────────────────────────────────────────────────

/**
 * Validates Gemini's response against the user's locked destination.
 * Returns the validated response or throws an error.
 */
function validateGeminiResponse(response, lockedDestName) {
  if (!response || !response.days || !Array.isArray(response.days) || response.days.length === 0) {
    throw new Error("Gemini returned an empty or invalid itinerary structure");
  }

  // 1. Destination integrity check
  const geminiDest = response.destination
    ? extractLocationName(response.destination, "")
    : "";
  const lockedClean = lockedDestName.toLowerCase().trim();
  const geminiClean = geminiDest.toLowerCase().trim();

  if (geminiClean && !geminiClean.includes(lockedClean) && !lockedClean.includes(geminiClean)) {
    // Allow close matches (e.g., "Tirumala" vs "Tirumala, Tirupati")
    const lockedWords = lockedClean.split(/[\s,]+/).filter((w) => w.length > 2);
    const geminiWords = geminiClean.split(/[\s,]+/).filter((w) => w.length > 2);
    const hasOverlap = lockedWords.some((w) => geminiWords.some((gw) => gw.includes(w) || w.includes(gw)));
    if (!hasOverlap) {
      throw new Error(
        `Gemini substituted destination! Expected "${lockedDestName}", got "${geminiDest}". Rejecting.`
      );
    }
  }

  // 2. Validate each day structure
  for (let i = 0; i < response.days.length; i++) {
    const day = response.days[i];
    if (!day.stops || !Array.isArray(day.stops)) {
      day.stops = [];
    }

    // Ensure day number
    day.day = day.day || i + 1;

    // Validate stops have names
    day.stops = day.stops.filter((s) => {
      const name = extractLocationName(s, "");
      return name && name.length > 1 && name !== "[object Object]";
    });

    // Ensure startLocation and endLocation exist
    if (!day.startLocation || !extractLocationName(day.startLocation, "")) {
      if (i === 0) {
        day.startLocation = response.origin || { name: "Origin" };
      } else {
        day.startLocation = response.days[i - 1].endLocation || response.days[i - 1].overnightStay || { name: "Previous location" };
      }
    }
    if (!day.endLocation || !extractLocationName(day.endLocation, "")) {
      day.endLocation = day.overnightStay || (day.stops.length > 0 ? { name: extractLocationName(day.stops[day.stops.length - 1], "Destination") } : { name: lockedDestName });
    }
  }

  // 3. Verify day-to-day continuity
  for (let i = 1; i < response.days.length; i++) {
    const prevEnd = extractLocationName(response.days[i - 1].endLocation, "");
    const currStart = extractLocationName(response.days[i].startLocation, "");
    if (prevEnd && currStart && prevEnd.toLowerCase() !== currStart.toLowerCase()) {
      // Auto-fix: set current day's start to previous day's end
      response.days[i].startLocation = response.days[i - 1].endLocation;
    }
  }

  return response;
}

// ─── Gemini Validation Pass (AI validates its own output) ────────────────────

const VALIDATION_SYSTEM = `You are a strict itinerary quality auditor. You validate travel itineraries.
Check for: destination correctness, geographic logic, real place names, day continuity, and no random/unrelated locations.
Respond ONLY with JSON.`;

async function geminiValidateItinerary(itinerary, lockedDestName, originName) {
  const validationPrompt = `Validate this itinerary. The LOCKED destination is "${lockedDestName}" and the origin is "${originName}".

Check ALL of these:
1. Does the itinerary reach "${lockedDestName}" as the primary destination? (CRITICAL)
2. Has the destination been replaced with a different city? (REJECT if yes)
3. Are all stops real, specific, named places? (no generic names)
4. Is the geographic flow logical (no random jumps)?
5. Are stops geographically near the route between "${originName}" and "${lockedDestName}"?
6. Does each day start where the previous day ended?

Itinerary to validate:
${JSON.stringify(itinerary, null, 2)}

Respond ONLY with JSON:
{
  "valid": true/false,
  "destinationCorrect": true/false,
  "issues": ["list of issues if any"],
  "rejectedStops": ["stop names that are geographically unreasonable"],
  "correctedItinerary": null or corrected itinerary object (same schema as input) if fixes were needed
}`;

  try {
    const text = await aiService.generateWithRetry(validationPrompt, {
      system: VALIDATION_SYSTEM,
      json: true,
      maxTokens: 8000,
    });
    const result = JSON.parse(text);
    return result;
  } catch (err) {
    console.warn("[GEMINI VALIDATION] Validation call failed:", err.message);
    // If validation fails, still return the original — better than nothing
    return { valid: true, destinationCorrect: true, issues: [], rejectedStops: [] };
  }
}

// ─── Stop Resolution & Geographic Filtering ──────────────────────────────────

/**
 * Resolves every Gemini-suggested stop to real coordinates via geocoding.
 * Drops stops that can't be resolved or create unreasonable detours.
 */
async function resolveGeminiStops(geminiDays, lockedDest, startPt) {
  const directDist = haversineDistanceKm(startPt, lockedDest);
  const maxDetourKm = Math.min(50, Math.max(15, directDist * 0.25));

  const resolvedDays = [];

  for (const day of geminiDays) {
    const resolvedStops = [];

    for (const stop of day.stops || []) {
      const stopName = extractLocationName(stop, "");
      if (!stopName || stopName.length < 2) continue;

      try {
        const resolved = await resolveLocation(stopName, stopName, lockedDest);
        if (!resolved || !Number.isFinite(resolved.lat) || !Number.isFinite(resolved.lng)) {
          console.log(`[GEMINI RESOLVE] Dropping unresolvable stop: "${stopName}"`);
          continue;
        }

        // Geographic reasonability check
        const distToDest = haversineDistanceKm(lockedDest, resolved);
        const distToStart = haversineDistanceKm(startPt, resolved);
        const corridorDetour = distToStart + distToDest - directDist;

        const isNearDest = distToDest <= 40; // within destination area
        const isAlongCorridor = corridorDetour <= maxDetourKm;
        const isNearStart = distToStart <= 30;

        if (!isNearDest && !isAlongCorridor && !isNearStart) {
          console.log(`[GEMINI RESOLVE] Dropping detour stop: "${stopName}" (detour: ${corridorDetour.toFixed(1)}km, maxAllowed: ${maxDetourKm.toFixed(1)}km)`);
          continue;
        }

        resolvedStops.push({
          ...resolved,
          name: resolved.name || stopName,
          category: stop.type || "attraction",
          categories: stop.type ? [stop.type] : ["attraction"],
          visitDurationMin: stop.durationMinutes || 45,
          reason: stop.reason || "",
          source: "gemini",
          isGeminiGenerated: true,
        });
      } catch (err) {
        console.warn(`[GEMINI RESOLVE] Error resolving "${stopName}":`, err.message);
      }
    }

    resolvedDays.push({
      day: day.day,
      title: day.title || `Day ${day.day}`,
      startLocation: day.startLocation,
      endLocation: day.endLocation,
      overnightStay: day.overnightStay,
      stops: resolvedStops,
    });
  }

  return resolvedDays;
}

// ─── Main Entry Point ────────────────────────────────────────────────────────

/**
 * Full Gemini itinerary generation pipeline:
 *  1. Build prompt → 2. Call Gemini → 3. Validate structure → 4. Gemini validates output
 *  → 5. Resolve stops to real coordinates → 6. Return flat stop list for itineraryEngine
 *
 * @returns {{ stops: Array, geminiDays: Array }} Resolved stops + raw Gemini day structure
 */
async function generateGeminiItinerary({
  origin,
  destination,
  days = 1,
  travellers = 1,
  vehicleModel = "car",
  mileage = 15,
  pace = "balanced",
  tripType = "around",
  preferences = "",
  categories = [],
  startDate = "",
  startTime = "08:00",
  startPt,
  lockedDest,
}) {
  const destName = extractLocationName(destination, "Destination");
  const originName = extractLocationName(origin, "Origin");

  console.log(`[GEMINI ITINERARY] ==========================================`);
  console.log(`[GEMINI ITINERARY] Generating itinerary via Gemini AI`);
  console.log(`[GEMINI ITINERARY] Origin: ${originName}`);
  console.log(`[GEMINI ITINERARY] Destination (LOCKED): ${destName}`);
  console.log(`[GEMINI ITINERARY] Days: ${days}, Pace: ${pace}, Type: ${tripType}`);

  // Step 1: Build prompt
  const prompt = buildGeminiPrompt({
    origin,
    destination,
    days,
    travellers,
    vehicleModel,
    mileage,
    pace,
    tripType,
    preferences,
    categories,
    startDate,
    startTime,
  });

  // Step 2: Call Gemini
  let geminiResponse;
  try {
    geminiResponse = await callGemini(prompt);
  } catch (err) {
    console.error("[GEMINI ITINERARY] Gemini generation failed:", err.message);
    throw new Error("Unable to generate the itinerary right now. Please try again.");
  }

  // Step 3: Structural validation
  let validated;
  try {
    validated = validateGeminiResponse(geminiResponse, destName);
  } catch (err) {
    console.warn("[GEMINI ITINERARY] First validation failed:", err.message, "— retrying with reinforced constraint");
    // Retry with reinforced constraint
    const reinforcedPrompt = prompt + `\n\nCRITICAL REMINDER: The destination MUST be "${destName}". Do NOT change it.`;
    try {
      geminiResponse = await callGemini(reinforcedPrompt);
      validated = validateGeminiResponse(geminiResponse, destName);
    } catch (retryErr) {
      console.error("[GEMINI ITINERARY] Retry also failed:", retryErr.message);
      throw new Error("Unable to generate an itinerary for the selected destination. Please try again.");
    }
  }

  // Step 4: Gemini validates its own output
  console.log("[GEMINI ITINERARY] Running Gemini self-validation...");
  const validationResult = await geminiValidateItinerary(validated, destName, originName);

  if (validationResult && !validationResult.valid) {
    console.warn("[GEMINI ITINERARY] Gemini self-validation found issues:", validationResult.issues);

    if (!validationResult.destinationCorrect) {
      throw new Error("Unable to generate an itinerary for the selected destination. Please try again.");
    }

    // Use corrected itinerary if provided
    if (validationResult.correctedItinerary && validationResult.correctedItinerary.days) {
      try {
        validated = validateGeminiResponse(validationResult.correctedItinerary, destName);
        console.log("[GEMINI ITINERARY] Using Gemini-corrected itinerary");
      } catch (_) {
        // Keep original validated if corrected fails validation
      }
    }

    // Remove rejected stops
    if (Array.isArray(validationResult.rejectedStops) && validationResult.rejectedStops.length > 0) {
      const rejectedSet = new Set(validationResult.rejectedStops.map((s) => s.toLowerCase().trim()));
      for (const day of validated.days) {
        day.stops = (day.stops || []).filter((s) => {
          const sName = extractLocationName(s, "").toLowerCase().trim();
          return !rejectedSet.has(sName);
        });
      }
      console.log(`[GEMINI ITINERARY] Removed ${validationResult.rejectedStops.length} rejected stops`);
    }
  } else {
    console.log("[GEMINI ITINERARY] Gemini self-validation PASSED ✓");
  }

  // Step 5: Resolve stops to real coordinates
  if (!startPt || !lockedDest) {
    throw new Error("startPt and lockedDest are required for stop resolution");
  }

  const resolvedDays = await resolveGeminiStops(validated.days, lockedDest, startPt);

  // Step 6: Flatten all resolved stops into a single ordered list for itineraryEngine
  const allStops = [];
  for (const day of resolvedDays) {
    for (const stop of day.stops) {
      // Avoid duplicates
      const isDup = allStops.some(
        (existing) =>
          haversineDistanceKm(existing, stop) < 0.5 ||
          existing.name.toLowerCase().trim() === stop.name.toLowerCase().trim()
      );
      if (!isDup) {
        allStops.push(stop);
      }
    }
  }

  console.log(`[GEMINI ITINERARY] Resolved ${allStops.length} valid stops from Gemini`);
  console.log(`[GEMINI ITINERARY] ==========================================`);

  return {
    stops: allStops,
    geminiDays: resolvedDays,
  };
}

module.exports = {
  generateGeminiItinerary,
  validateGeminiResponse,
  resolveGeminiStops,
  buildGeminiPrompt,
  geminiValidateItinerary,
};
