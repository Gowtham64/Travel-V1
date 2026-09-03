const axios = require("axios");

// Provider-agnostic AI. Set AI_PROVIDER = gemini | groq | openrouter to force one,
// otherwise auto-detect from whichever key is present. Gemini is preferred when
// its key is set — its free tier is far larger than Groq's (which caps at 200k
// tokens/day per model and was returning 429s once exhausted).
const PROVIDER = (
  process.env.AI_PROVIDER ||
  (process.env.GEMINI_API_KEY || process.env.GOOGLE_API_KEY
    ? "gemini"
    : process.env.GROQ_API_KEY
    ? "groq"
    : process.env.OPENROUTER_API_KEY
    ? "openrouter"
    : "gemini")
).toLowerCase();

const GEMINI_KEY = process.env.GEMINI_API_KEY || process.env.GOOGLE_API_KEY;
// gemini-2.0-flash was retired; gemini-3.6-flash is the current fast model.
const GEMINI_MODEL = process.env.GEMINI_MODEL || "gemini-3.6-flash";
const GROQ_KEY = process.env.GROQ_API_KEY;
// Groq decommissioned llama-3.3-70b-versatile for this key (404). Default to a
// currently-available production model; override with GROQ_MODEL if needed.
const GROQ_MODEL = process.env.GROQ_MODEL || "openai/gpt-oss-20b";
const OPENROUTER_KEY = process.env.OPENROUTER_API_KEY;
const OPENROUTER_MODEL = process.env.OPENROUTER_MODEL || "meta-llama/llama-3.3-70b-instruct:free";

const ACTIVE_MODEL = PROVIDER === "groq" ? GROQ_MODEL : PROVIDER === "openrouter" ? OPENROUTER_MODEL : GEMINI_MODEL;

class AiConfigError extends Error {}

function activeKey() {
  if (PROVIDER === "groq") return GROQ_KEY;
  if (PROVIDER === "openrouter") return OPENROUTER_KEY;
  return GEMINI_KEY;
}

/** Low-level text generation, dispatched to the configured provider. */
async function generate(prompt, opts = {}) {
  const key = activeKey();
  if (!key) throw new AiConfigError(`No API key set for AI provider "${PROVIDER}"`);
  return PROVIDER === "gemini"
    ? geminiGenerate(prompt, opts, key)
    : openaiCompatGenerate(prompt, opts, key);
}

async function geminiGenerate(prompt, opts, key) {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(GEMINI_MODEL)}:generateContent?key=${key}`;
  const body = { contents: [{ role: "user", parts: [{ text: prompt }] }], generationConfig: { temperature: 0.7 } };
  if (opts.system) body.systemInstruction = { parts: [{ text: opts.system }] };
  if (opts.json) body.generationConfig.responseMimeType = "application/json";
  if (opts.maxTokens) body.generationConfig.maxOutputTokens = opts.maxTokens;
  const res = await axios.post(url, body, { headers: { "Content-Type": "application/json" }, timeout: 30000 });
  return (res.data?.candidates?.[0]?.content?.parts || []).map((p) => p.text || "").join("").trim();
}

// Groq and OpenRouter both speak the OpenAI chat-completions format.
async function openaiCompatGenerate(prompt, opts, key) {
  const base = PROVIDER === "groq" ? "https://api.groq.com/openai/v1" : "https://openrouter.ai/api/v1";
  // Allow a per-call model override (e.g. a stronger model for itineraries).
  const model = opts.model || (PROVIDER === "groq" ? GROQ_MODEL : OPENROUTER_MODEL);
  const messages = [];
  if (opts.system) messages.push({ role: "system", content: opts.system });
  messages.push({ role: "user", content: prompt });
  const body = { model, messages, temperature: 0.7 };
  if (opts.json) body.response_format = { type: "json_object" };
  // gpt-oss models are reasoning models: without this they spend a large,
  // unpredictable share of the token budget on hidden reasoning, which can
  // starve (or truncate) the actual JSON output. "low" keeps tokens for output.
  if (opts.reasoningEffort) body.reasoning_effort = opts.reasoningEffort;
  // Raise the output cap for long structured responses (e.g. multi-day
  // itineraries) so the JSON isn't truncated mid-object → 400 "invalid JSON".
  if (opts.maxTokens) {
    body.max_tokens = opts.maxTokens;
    body.max_completion_tokens = opts.maxTokens;
  }
  const res = await axios.post(`${base}/chat/completions`, body, {
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${key}`,
      // OpenRouter likes these (optional but recommended).
      "HTTP-Referer": "https://gowtham64.github.io/Travel-V1/",
      "X-Title": "Voyplan",
    },
    timeout: 60000,
  });
  return (res.data?.choices?.[0]?.message?.content || "").trim();
}

// Accepts a bare JSON array OR an object like {"places":[...]}.
function safeParsePlaces(text) {
  try {
    let data = JSON.parse(text);
    if (data && !Array.isArray(data) && Array.isArray(data.places)) data = data.places;
    if (Array.isArray(data)) {
      return data
        .filter((p) => p && p.name)
        .slice(0, 12)
        .map((p) => ({ name: String(p.name), area: p.area ? String(p.area) : "", why: p.why ? String(p.why) : "" }));
    }
  } catch (_) {/* fall through */}
  return [];
}

const PLACES_JSON_HINT =
  'Respond ONLY with JSON of the form {"places":[{"name":"","area":"","why":""}]} — no prose, no markdown.';

async function recommendStops({ start, end, waypoints = [] }) {
  const via = waypoints.length ? ` via ${waypoints.join(", ")}` : "";
  const prompt =
    `Suggest up to 8 genuinely notable, popular places to stop and visit on a road trip ` +
    `from "${start}" to "${end}"${via}. Prefer well-known attractions, viewpoints, temples, ` +
    `forts, waterfalls, lakes and towns roughly on or near the route. ${PLACES_JSON_HINT}`;
  return safeParsePlaces(await generate(prompt, {
    system: "You are a concise, accurate India-aware road-trip guide. Only suggest real places.",
    json: true,
  }));
}

async function searchPlaces({ query, near }) {
  const qClean = (query || "").trim().toLowerCase();
  try {
    const anchor = near ? ` near ${near}` : "";
    const prompt = `Find up to 8 real, specific places matching this request${anchor}: "${query}". ${PLACES_JSON_HINT}`;
    const res = safeParsePlaces(await generate(prompt, {
      system: "You are a concise, accurate travel search assistant. Only return real, specific places.",
      json: true,
    }));
    if (res && res.length > 0) return res;
  } catch (err) {
    console.warn("AI searchPlaces provider error, using fallback matching:", err.message);
  }

  // Fallback to Curated Knowledge & Temples
  const fallback = [];
  for (const t of CURATED_TEMPLES) {
    if (t.name.toLowerCase().includes(qClean) || t.deity.toLowerCase().includes(qClean) || t.city.toLowerCase().includes(qClean) || qClean.includes(t.name.toLowerCase())) {
      fallback.push({
        name: t.name,
        area: t.city,
        why: `🛕 ${t.deity} · ⭐ ${t.rating} · ${t.highlight}`
      });
    }
  }
  if (fallback.length > 0) return fallback;

  return [
    {
      name: query.trim(),
      area: near || "Destination Area",
      why: "Selected place & attraction"
    }
  ];
}

// Parse the AI's travel-options JSON into clean flight / train / hotel arrays.
function safeParseTravelOptions(text) {
  const S = (v) => (v == null ? "" : String(v)).trim();
  try {
    const d = JSON.parse(text) || {};
    const flights = (Array.isArray(d.flights) ? d.flights : []).slice(0, 5).map((f) => ({
      airline: S(f.airline),
      flightNo: S(f.flightNo),
      route: S(f.route),
      stops: S(f.stops),
      duration: S(f.duration || f.durationHrs),
      priceRange: S(f.priceRange),
      note: S(f.note),
    })).filter((f) => f.airline || f.route);
    const trains = (Array.isArray(d.trains) ? d.trains : []).slice(0, 5).map((t) => ({
      operator: S(t.operator),
      name: S(t.name),
      route: S(t.route),
      duration: S(t.duration || t.durationHrs),
      priceRange: S(t.priceRange),
      note: S(t.note),
    })).filter((t) => t.operator || t.name || t.route);
    const hotels = (Array.isArray(d.hotels) ? d.hotels : []).slice(0, 6).map((h) => ({
      name: S(h.name),
      area: S(h.area),
      pricePerNight: S(h.pricePerNight),
      rating: S(h.rating),
      note: S(h.note),
    })).filter((h) => h.name);
    return { flights, trains, hotels };
  } catch (_) {
    return { flights: [], trains: [], hotels: [] };
  }
}

/**
 * Suggest realistic flight / train / hotel options for a journey. These are
 * AI-generated typical options (routes, airlines, well-known hotels, TYPICAL
 * price ranges) to help the traveller decide — NOT live availability or quotes.
 */
async function travelOptions({ from, to, startDate = "", travellers = 1, nights = 0 }) {
  if (!to) return { flights: [], trains: [], hotels: [] };
  const origin = from ? `"${from}"` : "the traveller's origin";
  const dateLine = startDate ? `around ${startDate} ` : "";
  const paxLine = Number(travellers) > 1 ? `for ${travellers} travellers ` : "";
  const nightsLine = Number(nights) > 0 ? `staying ${nights} night(s) ` : "";
  const prompt =
    `Suggest realistic travel and stay options for a trip from ${origin} to "${to}" ${dateLine}${paxLine}${nightsLine}. ` +
    `flights: 2–4 realistic airline options for this route. Depart from the NEAREST major airport to the ` +
    `origin and name it in the route (e.g. Bengaluru BLR for Mandya). Prefer a NON-STOP flight when one ` +
    `genuinely operates between these cities; if NO direct flight exists, give the best CONNECTING options ` +
    `via a sensible hub — set "stops" to the layover airport/city (e.g. "Dubai (DXB)") — and you may use an ` +
    `alternative nearby origin airport if it gives a better connection. Each: airline, a plausible flightNo ` +
    `(two numbers for a connection, e.g. "EK 569 / EK 201"), route with airport codes, "stops" ("Non-stop" or ` +
    `the layover), total "duration" like "18h 45m", a TYPICAL one-way fare "priceRange" in INR like ` +
    `"₹55,000–75,000", and a short note. Include a non-stop first if available, then connecting alternatives. ` +
    `Only include flights if flying is sensible for this route. ` +
    `trains: 1–3 realistic train options ONLY IF a train journey is genuinely practical between these places ` +
    `(operator, train name/number, route, duration, typical INR priceRange, note); use an EMPTY array if trains ` +
    `cannot make this journey (e.g. across an ocean). ` +
    `hotels: 3–5 real, well-known hotels in or near "${to}" (name, area/neighbourhood, typical pricePerNight in INR, ` +
    `star rating like "4★", short note). ` +
    `All prices are TYPICAL estimates, not live quotes. Use only real airlines, trains and hotels. ` +
    `Respond ONLY as JSON: {"flights":[{"airline":"","flightNo":"","route":"","stops":"","duration":"","priceRange":"","note":""}],` +
    `"trains":[{"operator":"","name":"","route":"","duration":"","priceRange":"","note":""}],` +
    `"hotels":[{"name":"","area":"","pricePerNight":"","rating":"","note":""}]} — no prose, no markdown.`;
  const text = await generateWithRetry(prompt, {
    system:
      "You are a knowledgeable travel booking assistant. Suggest realistic, real-world flight, train and " +
      "hotel options with typical (not live) prices. Only real airlines, trains and hotels. Output strict JSON.",
    json: true,
    reasoningEffort: PROVIDER === "groq" ? "low" : undefined,
    maxTokens: 3000,
  });
  return safeParseTravelOptions(text);
}

async function ask({ question, context }) {
  const ctx = context
    ? `\n\nTrip context:\n${Object.entries(context)
        .filter(([, v]) => v != null && v !== "")
        .map(([k, v]) => `- ${k}: ${v}`)
        .join("\n")}`
    : "";
  return generate(`${question}${ctx}`, {
    system:
      "You are Voyplan's road-trip assistant. Be concise, practical and specific. " +
      "Use short paragraphs or bullet points. When asked for an itinerary, give a clear " +
      "day-by-day plan with drive legs, stops, and meal/rest suggestions.",
  });
}

// Accepts {"days":[...]} or a bare array; normalizes each day + activity.
function safeParseItinerary(text, maxDays) {
  try {
    let data = JSON.parse(text);
    if (Array.isArray(data)) data = { days: data };
    const days = Array.isArray(data.days) ? data.days : [];
    return days
      .slice(0, Math.max(1, maxDays))
      .map((d, i) => ({
        day: Number(d.day) || i + 1,
        title: String(d.title || `Day ${i + 1}`),
        activities: (Array.isArray(d.activities) ? d.activities : [])
          .slice(0, 8)
          .map((a) => ({
            part: String(a.part || "Day"),
            time: a.time ? String(a.time) : "",
            title: String(a.title || ""),
            note: a.note ? String(a.note) : "",
          }))
          .filter((a) => a.title),
      }))
      .filter((d) => d.activities.length);
  } catch (_) {
    return [];
  }
}

/** Generates a structured, day-by-day activity itinerary. */
async function buildItinerary({ start, end, days = 1, waypoints = [], travellers = 1, purpose = "", startDate = "", startTime = "", weather = "" }) {
  const via = waypoints.length ? ` via ${waypoints.join(", ")}` : "";
  const weatherLine = weather
    ? `Plan around this forecast: ${weather}. Schedule outdoor sights, viewpoints and walks during clear/dry ` +
      `windows, and prefer indoor options (museums, temples, cafes, malls) when rain is likely or it is very hot. ` +
      `If a day looks wet, say so briefly in that day's title. `
    : "";
  const prompt =
    `Create a practical, realistic day-by-day travel itinerary for a road trip from "${start}" to "${end}"${via}, ` +
    `lasting ${days} day(s) for ${travellers} traveller(s)${purpose ? ` (${purpose} trip)` : ""}` +
    `${startDate ? `, starting ${startDate}` : ""}${startTime ? ` at about ${startTime}` : ""}. ` +
    `Begin the first day's first activity at roughly the given start time. ` +
    weatherLine +
    `For each day give 3 to 5 activities spread across Morning, Afternoon, Evening and Night. ` +
    `Prefer real, well-known sights, food stops and experiences on or near the route. Keep each note short ` +
    `(max ~12 words). Respond ONLY as JSON: ` +
    `{"days":[{"day":1,"title":"","activities":[{"part":"Morning","time":"09:00","title":"","note":""}]}]} ` +
    `— no prose, no markdown.`;
  const text = await generate(prompt, {
    system: "You are an expert, India-aware road-trip planner. Only suggest real places. Adapt the plan to the weather. Output strict JSON.",
    json: true,
  });
  return safeParseItinerary(text, days);
}

/** Diagnostic: models this provider/key can use. */
async function listModels() {
  const key = activeKey();
  if (!key) throw new AiConfigError(`No API key set for AI provider "${PROVIDER}"`);
  if (PROVIDER === "gemini") {
    const res = await axios.get(`https://generativelanguage.googleapis.com/v1beta/models?key=${key}&pageSize=100`, { timeout: 15000 });
    return (res.data?.models || [])
      .filter((m) => (m.supportedGenerationMethods || []).includes("generateContent"))
      .map((m) => (m.name || "").replace(/^models\//, ""));
  }
  const base = PROVIDER === "groq" ? "https://api.groq.com/openai/v1" : "https://openrouter.ai/api/v1";
  const res = await axios.get(`${base}/models`, { headers: { Authorization: `Bearer ${key}` }, timeout: 15000 });
  return (res.data?.data || []).map((m) => m.id).slice(0, 60);
}

// ── Smart, time-blocked itinerary (AI travel-assistant) ───────────────────────

// Classify a travel/return block's mode of transport. Trusts an explicit
// travelMode from the AI when present; otherwise infers from the title/reason
// keywords, falling back to "drive". Non-travel blocks get "".
function normalizeTravelMode(b) {
  const type = String(b.type || "");
  if (type !== "travel" && type !== "return") return "";
  const explicit = String(b.travelMode || "").toLowerCase().trim();
  const allowed = ["drive", "flight", "train", "bus", "ferry", "walk"];
  if (allowed.includes(explicit)) return explicit;
  const s = `${b.title || ""} ${b.reason || ""}`.toLowerCase();
  if (/\bflight\b|\bfly\b|\bairways?\b|\bair travel\b/.test(s)) return "flight";
  if (/\btrain\b|\brail\b|\bexpress\b(?!way)|\bmetro\b/.test(s)) return "train";
  if (/\bferry\b|\bboat\b|\bcruise\b/.test(s)) return "ferry";
  if (/\bbus\b|\bcoach\b/.test(s)) return "bus";
  // A very long single leg is almost certainly a flight, not a drive.
  if ((Number(b.distanceKm) || 0) > 700) return "flight";
  return "drive";
}

function safeParseSmart(text) {
  try {
    const data = JSON.parse(text);
    const days = Array.isArray(data?.days) ? data.days : [];
    return days
      .map((d, i) => ({
        day: Number(d.day) || i + 1,
        date: d.date ? String(d.date) : "",
        title: d.title ? String(d.title) : `Day ${i + 1}`,
        blocks: (Array.isArray(d.blocks) ? d.blocks : [])
          .map((b) => ({
            start: String(b.start || ""),
            end: String(b.end || ""),
            type: String(b.type || "activity"),
            title: String(b.title || b.place || ""),
            place: String(b.place || ""),
            durationMin: Number(b.durationMin) || 0,
            travelMin: Number(b.travelMin) || 0,
            distanceKm: Number(b.distanceKm) || 0,
            breakType: b.breakType ? String(b.breakType) : "",
            reason: b.reason ? String(b.reason) : "",
            travelMode: normalizeTravelMode(b),
            categories: Array.isArray(b.categories)
              ? b.categories.map(String).filter(Boolean)
              : (b.category ? [String(b.category)] : []),
            whyIncluded: b.whyIncluded ? String(b.whyIncluded) : "",
          }))
          .filter((b) => b.title || b.type),
      }))
      .filter((d) => d.blocks.length);
  } catch (_) {/* fall through */}
  return [];
}

// Shared planning rules, reused by every batch prompt.
const ITINERARY_RULES =
  `Think carefully about the REAL geographic location of each named place. Use only real, ` +
  `specific, well-known places (never generic names like "Temple 1"). Order stops to MINIMISE ` +
  `backtracking — group nearby places on the same day. Schedule each day morning to night as an ` +
  `ordered sequence of time blocks. Insert breaks WITHOUT being asked: breakfast (~08:00), lunch ` +
  `(~13:00), dinner (~20:00), an afternoon coffee break, rest after long/strenuous activity, ` +
  `hotel check-in on the FIRST day and check-out on the FINAL day, transfer time between places. ` +
  `Every "travel"/"return" block MUST include "travelMode": drive|flight|train|bus|ferry|walk. ` +
  `Pick the REALISTIC mode: for an overseas trip or any leg over ~700 km use "flight" (with short ` +
  `"drive" airport transfers either side); use "train"/"bus" only if that's genuinely how people ` +
  `travel it; otherwise "drive". For a DRIVE leg give an ACCURATE road distance (km) and a time ` +
  `consistent with it (~30 km/h city, ~55 km/h highway; 12 km ≈ 25 min, never 5). For a FLIGHT leg ` +
  `distanceKm is great-circle air distance and travelMin the in-air time (e.g. BLR→Dubai ≈ 5139 km, ` +
  `≈ 240 min), NOT a driving time. travelMin and distanceKm must agree; a 0 km transfer is 0 min. ` +
  `Use realistic visit durations (major temple 1.5–3 h, viewpoint 30–45 min, museum 1–2 h). Never ` +
  `place sightseeing inside a meal window. Keep each reason under ~10 words. Block "type" is one of: ` +
  `start, activity, travel, meal, coffee, rest, checkin, checkout, buffer, shopping, freetime, return. ` +
  `For meal blocks set breakType to breakfast|lunch|dinner. ` +
  `For activity blocks, ALWAYS include "categories": ["CategoryName", ...] matching the user's selected preferences, and "whyIncluded": "Clear explanation of why this place matches the user's category preference and route."`;

const ITINERARY_JSON_HINT =
  `Respond ONLY as JSON: {"days":[{"day":1,"date":"","title":"","blocks":[{"start":"08:00",` +
  `"end":"08:30","type":"meal","title":"Breakfast","place":"","durationMin":30,"travelMin":0,` +
  `"distanceKm":0,"breakType":"breakfast","reason":"","travelMode":"","categories":[],"whyIncluded":""}]}]} — travel blocks set ` +
  `travelMode; activity blocks set categories and whyIncluded; no prose, no markdown.`;

const ITINERARY_SYSTEM =
  "You are an expert, meticulous, world-aware travel planner with strong geographic knowledge. " +
  "You produce realistic, well-sequenced, time-blocked itineraries with automatic meal/rest " +
  "breaks and accurate, internally-consistent travel distances/times. Only suggest real, specific " +
  "places. Output strict, COMPLETE JSON for exactly the requested days — never truncate.";

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

// Call generate() with a couple of retries on transient (rate-limit / 5xx) errors.
async function generateWithRetry(prompt, opts, tries = 3) {
  let lastErr;
  for (let i = 0; i < tries; i += 1) {
    try {
      return await generate(prompt, opts);
    } catch (err) {
      lastErr = err;
      const status = err.response ? err.response.status : 0;
      // Only retry things that might succeed on a second try.
      if (status && status !== 429 && status < 500) break;
      if (i < tries - 1) await sleep(1200 * (i + 1));
    }
  }
  throw lastErr;
}

/**
 * Generate a realistic, time-blocked day-by-day itinerary with automatic
 * meal/rest breaks, travel time and per-block reasoning.
 */
async function smartItinerary({
  destination,
  startLocation = "",
  places = [],
  startDate = "",
  startTime = "08:00",
  endDate = "",
  endTime = "",
  durationDays = 1,
  mode = "balanced",
  preferences = "",
  directive = "",
  selectedCategories = [],
  categoryPriorities = {},
  customPreferences = "",
}) {
  const total = Math.max(1, Math.min(Number(durationDays) || 1, 14));
  const placeLine = places.length ? `Must-visit specific places (spread across the trip): ${places.join(", ")}. ` : "";
  const paceLine =
    mode === "packed"
      ? "Pace: PACKED — fit in as much as reasonably possible, shorter breaks. "
      : mode === "relaxed"
      ? "Pace: RELAXED — fewer activities, longer meals/rest, plenty of free time. "
      : "Pace: BALANCED — a comfortable mix of sightseeing, meals and rest. ";
  
  const combinedPref = [preferences, customPreferences].filter(Boolean).join(". ");
  const prefLine = combinedPref ? `Traveller custom preferences: ${combinedPref}. ` : "";
  const directiveLine = directive ? `IMPORTANT adjustment for this version: ${directive}. ` : "";
  const homeLine = startLocation ? ` starting from the traveller's home "${startLocation}"` : "";

  // Build category constraint instructions
  let categoryConstraintLine = "";
  if (selectedCategories && selectedCategories.length) {
    const mustVisit = [];
    const wouldLike = [];
    const optional = [];
    for (const cat of selectedCategories) {
      const prio = (categoryPriorities && categoryPriorities[cat]) || "must_visit";
      if (prio === "must_visit") mustVisit.push(cat);
      else if (prio === "would_like") wouldLike.push(cat);
      else optional.push(cat);
    }
    categoryConstraintLine =
      `\nSTRICT PLACE PREFERENCE CONSTRAINTS (HARD RULES):\n` +
      `The traveller has selected the following place categories for this trip:\n` +
      (mustVisit.length ? `- MUST VISIT (Top Priority): ${mustVisit.join(", ")}\n` : "") +
      (wouldLike.length ? `- WOULD LIKE TO VISIT (Secondary Priority): ${wouldLike.join(", ")}\n` : "") +
      (optional.length ? `- OPTIONAL (Include only if convenient on route): ${optional.join(", ")}\n` : "") +
      `MANDATORY FILTERING & ROUTING RULES:\n` +
      `1. Every activity/sightseeing stop MUST belong to one of these selected categories.\n` +
      `2. DO NOT add attractions from unselected categories (e.g. no random shopping malls, nightlife, beaches, adventure parks, cafes, or unrelated tourist spots) unless explicitly selected by the user.\n` +
      `3. For every activity stop, populate "categories": [list of matched categories] and "whyIncluded": "Explanation of why this place matches user category preferences along the route."\n` +
      `4. Balance categories across the ${total} days following a logical sequence (Start -> Stop 1 -> Stop 2 -> Lunch -> Stop 3 -> Stay) without backtracking.\n`;
  }

  // Build the prompt for one batch of days [from..to] of a `total`-day round trip.
  function batchPrompt(from, to) {
    const isFirst = from === 1;
    const isLast = to === total;
    const count = to - from + 1;
    const dayWord = count === 1 ? `day ${from}` : `days ${from}–${to}`;
    let ctx =
      `You are planning a ${total}-day trip to "${destination}"${homeLine}, which starts on ` +
      `${startDate || "day 1"} at ${startTime}. Produce ONLY ${dayWord} of ${total}, as ${count} ` +
      `day object(s) numbered exactly ${from}${count > 1 ? `..${to}` : ""}. `;
    if (startLocation && isFirst) {
      ctx +=
        `This is a ROUND TRIP: day 1 MUST begin at "${startLocation}" with a travel block ` +
        `departing home to reach "${destination}" (realistic mode, distance & time), then hotel check-in. `;
    } else if (!isFirst) {
      ctx += `Continue seamlessly: the traveller is already at "${destination}" (resuming from their hotel). Do NOT repeat the outbound journey. `;
    }
    if (startLocation && isLast) {
      ctx +=
        `Day ${total} is the FINAL day and MUST end with hotel check-out and a "return" block taking ` +
        `the traveller ALL THE WAY BACK to "${startLocation}" (realistic mode, distance & time). `;
    }
    if (isLast && (endDate || endTime)) ctx += `The trip should end around ${endDate} ${endTime}. `;
    return ctx + placeLine + prefLine + paceLine + directiveLine + categoryConstraintLine + ITINERARY_RULES + " " + ITINERARY_JSON_HINT;
  }

  const MODELS =
    PROVIDER === "groq"
      ? ["openai/gpt-oss-120b", "openai/gpt-oss-20b", "llama-3.3-70b-versatile"]
      : [undefined];
  let days = [];
  let lastErr = null;
  for (const m of MODELS) {
    try {
      const text = await generateWithRetry(batchPrompt(1, total), {
        system: ITINERARY_SYSTEM,
        json: true,
        model: m,
        reasoningEffort: m && m.includes("gpt-oss") ? "low" : undefined,
        maxTokens: 7000,
      });
      days = safeParseSmart(text);
      if (days.length) break;
    } catch (err) {
      lastErr = err;
      const status = err.response ? err.response.status : 0;
      console.error(`Itinerary model ${m} failed:`, status, err.response ? JSON.stringify(err.response.data).slice(0, 200) : err.message);
      if (status !== 429) break;
    }
  }

  // If AI generation didn't return any days, generate an intelligent fallback plan
  if (!days.length) {
    console.log("Generating smart fallback itinerary for", destination);
    days = buildFallbackSmartItinerary({
      destination,
      startLocation,
      places,
      durationDays: total,
      startTime,
      preferences: combinedPref,
      selectedCategories,
      categoryPriorities,
      customPreferences,
    });
  }

  days = days.slice(0, total);
  days.forEach((d, i) => { d.day = i + 1; });
  return days;
}

const CURATED_ATTRACTIONS = [
  // --- Mangaluru & Udupi Coastal Circuit ---
  { name: "Kudroli Gokarnanatheshwara Temple", deity: "Lord Shiva & Navadurga Sanctum", city: "Mangaluru (Mangalore)", rating: "4.8", durationMin: 75, highlight: "Illuminated marble corridors, golden gopuram & sacred Pushkarini", categories: ["Temples & Religious Places", "Cultural Places", "Historical & Heritage Places"] },
  { name: "Panambur Beach & Water Sports", deity: "Arabian Sea Coastal Promenade", city: "Mangaluru (Mangalore)", rating: "4.7", durationMin: 90, highlight: "Jet skiing, boat rides, camel rides & sunset photography along Arabian Sea", categories: ["Beaches", "Famous City Attractions", "Instagrammable / Photography Spots"] },
  { name: "Tannirbhavi Beach & Tree Park", deity: "Scenic Pine Grove & Beach Front", city: "Mangaluru (Mangalore)", rating: "4.7", durationMin: 90, highlight: "Tranquil beach with dense pine canopy, ferry crossing & walking trails", categories: ["Beaches", "Nature & Forests", "Viewpoints & Scenic Places"] },
  { name: "Kadri Manjunath Temple & Ancient Caves", deity: "10th Century Lokeshwara Bronze Heritage", city: "Mangaluru (Mangalore)", rating: "4.8", durationMin: 75, highlight: "Historic hill shrine with natural mountain springs & Pandava caves", categories: ["Temples & Religious Places", "Historical & Heritage Places", "Hills & Mountains"] },
  { name: "St. Aloysius Chapel & Heritage Art Gallery", deity: "1899 Italian Frescoes & Canvas Murals", city: "Mangaluru (Mangalore)", rating: "4.8", durationMin: 60, highlight: "Magnificent Sistine Chapel-style ceiling frescoes by Italian Jesuit Bro. Moscheni", categories: ["Historical & Heritage Places", "Cultural Places", "Monuments & Landmarks"] },
  { name: "Pilikula Nisargadhama Biological Park", deity: "Eco-Education Botanical Reserve & Zoo", city: "Mangaluru (Mangalore)", rating: "4.7", durationMin: 150, highlight: "Safari zoo, heritage artisanal village, lake boating & 3D planetarium", categories: ["Wildlife & National Parks", "Nature & Forests", "Rivers, Lakes & Waterfalls"] },
  { name: "Sultan Battery & Gurupura Riverfront", deity: "Tipu Sultan 1784 Naval Watchtower", city: "Mangaluru (Mangalore)", rating: "4.6", durationMin: 60, highlight: "Historic black stone watchtower overlooking river mouth & boat jetty", categories: ["Forts & Palaces", "Historical & Heritage Places", "Rivers, Lakes & Waterfalls"] },
  { name: "Someshwara Beach & Rudra Shile Rocks", deity: "Sacred Sea Rocks & Beach Sunset", city: "Ullal, Mangaluru", rating: "4.7", durationMin: 75, highlight: "Dramatic large monolithic sea boulders & panoramic sunset viewpoint", categories: ["Beaches", "Viewpoints & Scenic Places", "Instagrammable / Photography Spots"] },
  { name: "Surathkal Lighthouse & Beach Lookout", deity: "1972 Coastal Lighthouse & Rocky Shore", city: "Surathkal, Mangaluru", rating: "4.7", durationMin: 60, highlight: "Panoramic 360-degree ocean lookout atop rocky coastal lighthouse hill", categories: ["Viewpoints & Scenic Places", "Beaches", "Monuments & Landmarks"] },
  { name: "Kateel Sri Durgaparameshwari Temple", deity: "Goddess Durga on Nandini River Island", city: "Kateel, Mangaluru", rating: "4.8", durationMin: 90, highlight: "Sacred river island sanctum surrounded by rushing streams of Nandini river", categories: ["Temples & Religious Places", "Rivers, Lakes & Waterfalls"] },
  { name: "Udupi Sri Krishna Matha & Temple Square", deity: "Lord Krishna & Kanakana Kindi", city: "Udupi", rating: "4.9", durationMin: 90, highlight: "Historic 13th-century Madhvacharya matha, golden ratha & holy pond", categories: ["Temples & Religious Places", "Cultural Places", "Famous / Must-Visit Places"] },
  { name: "Malpe Beach & St. Mary's Island", deity: "Unique Hexagonal Basalt Column Islands", city: "Malpe, Udupi", rating: "4.8", durationMin: 180, highlight: "Scenic ferry ride to million-year-old columnar basalt rock formations", categories: ["Beaches", "Nature & Forests", "Instagrammable / Photography Spots", "Famous / Must-Visit Places"] },

  // --- Chikmagalur & Western Ghats ---
  { name: "Mullayanagiri Peak & Trekking Ridge", deity: "Highest Peak in Karnataka (6330ft)", city: "Chikmagalur", rating: "4.8", durationMin: 150, highlight: "Sweeping Western Ghats mountain vistas, cool mist and hilltop temple", categories: ["Hills & Mountains", "Viewpoints & Scenic Places", "Instagrammable / Photography Spots"] },
  { name: "Baba Budangiri & Datta Peeta", deity: "Sacred Mountain Shrine & Caves", city: "Chikmagalur", rating: "4.7", durationMin: 120, highlight: "Dramatic mountain pass, historic caves and origin of Indian coffee", categories: ["Hills & Mountains", "Cultural Places", "Historical & Heritage Places"] },
  { name: "Hebbe Falls & Mountain Stream Trek", deity: "550ft Tiered Coffee Estate Waterfall", city: "Near Chikmagalur", rating: "4.8", durationMin: 180, highlight: "Exciting 4x4 jungle ride & trek through coffee plantations to roaring falls", categories: ["Rivers, Lakes & Waterfalls", "Nature & Forests", "Hills & Mountains"] },
  { name: "Z Point Sunset Lookout", deity: "Scenic Hill Ridge Viewpoint", city: "Kemmanagundi, Chikmagalur", rating: "4.7", durationMin: 90, highlight: "Thrilling cliffside walking trail with 360-degree green valley views", categories: ["Viewpoints & Scenic Places", "Hills & Mountains", "Instagrammable / Photography Spots"] },

  // --- Wayanad ---
  { name: "Banasura Sagar Dam & Speed Boating", deity: "Largest Earthen Dam in India", city: "Wayanad", rating: "4.7", durationMin: 120, highlight: "Speed boating in emerald reservoir surrounded by misty Banasura hills", categories: ["Famous Bridges / Dams", "Rivers, Lakes & Waterfalls", "Viewpoints & Scenic Places"] },
  { name: "Edakkal Caves & Ancient Stone Age Carvings", deity: "Neolithic Petroglyphs (6000 BCE)", city: "Wayanad", rating: "4.7", durationMin: 120, highlight: "Scenic uphill mountain trek to prehistoric rock engravings & valley view", categories: ["Historical & Heritage Places", "Hills & Mountains", "Cultural Places"] },
  { name: "Soochipara Waterfalls (Sentinel Rock)", deity: "3-Tiered Forest Mountain Cascade", city: "Meppadi, Wayanad", rating: "4.7", durationMin: 120, highlight: "Walk through tea plantations and lush evergreen forest to natural pool", categories: ["Rivers, Lakes & Waterfalls", "Nature & Forests", "Instagrammable / Photography Spots"] },
  { name: "Lakkidi View Point & Ghat Road Vista", deity: "Gateway to Wayanad High Mountain Pass", city: "Lakkidi, Wayanad", rating: "4.6", durationMin: 60, highlight: "Dramatic 700m high cliff edge looking over winding Thamarassery Churam", categories: ["Viewpoints & Scenic Places", "Hills & Mountains"] },

  // --- Mumbai ---
  { name: "Gateway of India & Apollo Bunder", deity: "Iconic 1924 Basalt Arch Monument", city: "Mumbai", rating: "4.8", durationMin: 90, highlight: "Overlooking Mumbai harbour, Taj Mahal Palace hotel & Arabian Sea boats", categories: ["Historical & Heritage Places", "Monuments & Landmarks", "Famous / Must-Visit Places"] },
  { name: "Bandra-Worli Sea Link & Promenade", deity: "Cable-Stayed Sea Bridge Engineering Marvel", city: "Mumbai", rating: "4.8", durationMin: 60, highlight: "Spectacular 8-lane cable-stayed bridge spanning Arabian sea waters", categories: ["Famous Bridges / Dams", "Viewpoints & Scenic Places", "Instagrammable / Photography Spots"] },
  { name: "Marine Drive & Queen's Necklace", deity: "Curved 3.6km Arabian Sea Coastal Boulevard", city: "Mumbai", rating: "4.8", durationMin: 90, highlight: "Panoramic sunset sea promenade illuminated like a necklace at night", categories: ["Viewpoints & Scenic Places", "Famous City Attractions", "Instagrammable / Photography Spots"] },
  { name: "Chhatrapati Shivaji Maharaj Terminus (CSMT)", deity: "UNESCO Victorian Gothic Masterpiece", city: "Mumbai", rating: "4.8", durationMin: 60, highlight: "Ornate turrets, stained glass and evening architectural lighting", categories: ["Historical & Heritage Places", "Monuments & Landmarks", "Famous / Must-Visit Places"] },
  { name: "Elephanta Caves & Island Ferry Ride", deity: "5th-Century Rock-Cut Shiva Temples", city: "Mumbai", rating: "4.7", durationMin: 180, highlight: "Scenic 1-hour harbour boat cruise to UNESCO Trimurti sculpture island", categories: ["Historical & Heritage Places", "Cultural Places", "Rivers, Lakes & Waterfalls"] },
  { name: "Sanjay Gandhi National Park & Kanheri Caves", deity: "Protected Forest Reserve & Buddhist Caves", city: "Mumbai", rating: "4.7", durationMin: 180, highlight: "Lush green forest, tiger/lion safari & 109 rock-cut ancient Buddhist caves", categories: ["Wildlife & National Parks", "Nature & Forests", "Hills & Mountains"] },
  { name: "Juhu Beach & Street Food Boulevard", deity: "Sunset Arabian Sea Beach", city: "Mumbai", rating: "4.6", durationMin: 90, highlight: "Famous Mumbai Pav Bhaji, Sev Puri & Arabian Sea evening breezes", categories: ["Beaches", "Famous Markets & Local Places", "Famous City Attractions"] },
  { name: "Colaba Causeway & Arts District", deity: "Bustling Heritage Bazaar & Cafes", city: "Mumbai", rating: "4.7", durationMin: 90, highlight: "Artisanal shopping, antique jewelry, street stalls & iconic cafes", categories: ["Famous Markets & Local Places", "Cultural Places"] },
  { name: "Shree Siddhivinayak Temple", deity: "Lord Ganesha (Gold-Plated Sanctum)", city: "Mumbai", rating: "4.8", durationMin: 75, highlight: "Historic 1801 inner gold-plated sanctum dedicated to Lord Ganesha", categories: ["Temples & Religious Places", "Famous / Must-Visit Places"] },

  // --- Tirupati / Tirumala ---
  { name: "Sri Venkateswara Swamy Temple", deity: "Lord Venkateswara (Balaji)", city: "Tirumala, Tirupati", rating: "4.8", durationMin: 240, wait: "SED (₹300): 3–4 hrs · SSD Slotted: 4–6 hrs · Free: 8–12 hrs", highlight: "Golden Ananda Nilayam vimana & Laddu prasadam", categories: ["Temples & Religious Places", "Famous / Must-Visit Places"] },
  { name: "Shri Varaha Swamy Temple", deity: "Lord Adi Varaha Swamy", city: "Tirumala, Tirupati", rating: "4.8", durationMin: 60, wait: "30–60 mins", highlight: "Holy Swami Pushkarini bank traditional first darshan", categories: ["Temples & Religious Places", "Historical & Heritage Places"] },
  { name: "Sri Kapileswara Swamy Temple & Kapila Theertham", deity: "Lord Shiva & Mountain Falls", city: "Tirupati", rating: "4.7", durationMin: 60, wait: "30–60 mins", highlight: "Sacred mountain waterfall & holy spring", categories: ["Temples & Religious Places", "Rivers, Lakes & Waterfalls", "Viewpoints & Scenic Places"] },
  { name: "Silathoranam Natural Rock Arch & Chakra Theertham", deity: "Rare Million-Year Geological Arch", city: "Tirumala", rating: "4.7", durationMin: 45, wait: "Tour: 30–45 mins", highlight: "Rare natural geological rock arch & holy waterbody", categories: ["Monuments & Landmarks", "Nature & Forests", "Instagrammable / Photography Spots"] },
  { name: "Sri Venkateswara National Park & Zoo Safari", deity: "Protected Flora, Fauna & Deer Park", city: "Tirupati", rating: "4.6", durationMin: 120, wait: "Safari: 1.5–2 hrs", highlight: "Lush wildlife habitat, bird watching & flora safari", categories: ["Wildlife & National Parks", "Nature & Forests"] },
  { name: "Chandragiri Fort & Raja Mahal Palace", deity: "Vijayanagara Imperial Architecture", city: "Chandragiri, Tirupati", rating: "4.7", durationMin: 90, wait: "Tour: 1–1.5 hrs", highlight: "11th-century royal palace, fortified walls & light show", categories: ["Forts & Palaces", "Historical & Heritage Places", "Monuments & Landmarks"] },
  { name: "Talakona Waterfalls & Valley Trek", deity: "Highest Waterfall in Andhra (270ft)", city: "Near Tirupati", rating: "4.7", durationMin: 150, wait: "Trek & Splash: 2–3 hrs", highlight: "Crystal clear cascades, canopy walkway & dense forest", categories: ["Rivers, Lakes & Waterfalls", "Nature & Forests", "Hills & Mountains"] },
  { name: "Sri Govindaraja Swamy Temple", deity: "Lord Govindaraja Swamy", city: "Tirupati", rating: "4.7", durationMin: 75, wait: "45–90 mins", highlight: "Towering 12th-century Raja Gopuram & bustling bazaar", categories: ["Temples & Religious Places", "Monuments & Landmarks", "Famous Markets & Local Places"] },
  { name: "Srikalahasti Temple", deity: "Lord Shiva (Kalahasteeswara)", city: "Srikalahasti", rating: "4.7", durationMin: 150, wait: "Rahu-Ketu: 2–3 hrs · General: 1–2 hrs", highlight: "Pancha Bhoota Vayu Lingam & Rahu-Ketu puja", categories: ["Temples & Religious Places", "Historical & Heritage Places"] },
  { name: "Kanipakam Vinayaka Temple", deity: "Lord Varasidhi Vinayaka", city: "Kanipakam", rating: "4.7", durationMin: 90, wait: "Special: 1–1.5 hrs · General: 2–3 hrs", highlight: "Swayambhu growing Ganesha in holy well", categories: ["Temples & Religious Places"] },

  // --- Mysuru & Srirangapatna ---
  { name: "Mysore Palace (Amba Vilas)", deity: "Wodeyar Royal Heritage & Durbar", city: "Mysuru", rating: "4.8", durationMin: 150, wait: "Palace Tour: 2–3 hrs", highlight: "Golden Throne, stained glass Kalyana Mantapa & illuminated facade", categories: ["Forts & Palaces", "Historical & Heritage Places", "Famous / Must-Visit Places"] },
  { name: "Sri Chamundeshwari Temple & Monolithic Nandi", deity: "Goddess Chamundeshwari & 360° City Vista", city: "Chamundi Hills, Mysuru", rating: "4.8", durationMin: 90, wait: "Special: 45–75 mins · General: 1.5–2.5 hrs", highlight: "Sacred hilltop Shakti Peetha & 16ft monolithic Nandi statue", categories: ["Temples & Religious Places", "Viewpoints & Scenic Places", "Hills & Mountains"] },
  { name: "Brindavan Gardens & Musical Fountain", deity: "Terraced Gardens & Kaveri Waterway", city: "Mysuru", rating: "4.7", durationMin: 120, wait: "Garden & Light Show: 2–2.5 hrs", highlight: "Terraced botanical walkways & synchronized musical dancing fountains", categories: ["Nature & Forests", "Rivers, Lakes & Waterfalls", "Famous City Attractions"] },
  { name: "Sri Chamarajendra Zoological Gardens (Mysore Zoo)", deity: "Historic 1892 Wildlife Habitat", city: "Mysuru", rating: "4.8", durationMin: 150, wait: "Zoo Walk: 2–3 hrs", highlight: "One of India's oldest zoos with giraffes, elephants & exotic birds", categories: ["Wildlife & National Parks", "Nature & Forests", "Famous / Must-Visit Places"] },
  { name: "Karanji Lake & Nature Park", deity: "Walk-Through Aviary & Boating", city: "Mysuru", rating: "4.6", durationMin: 75, wait: "Leisure: 1–1.5 hrs", highlight: "Scenic lake boating, butterfly park & India's largest walk-through aviary", categories: ["Rivers, Lakes & Waterfalls", "Nature & Forests", "Viewpoints & Scenic Places"] },
  { name: "KRS Dam (Krishna Raja Sagara Dam)", deity: "Historic Kaveri River Dam", city: "Mysuru", rating: "4.7", durationMin: 90, wait: "Dam Vista: 1–1.5 hrs", highlight: "Majestic reservoir dam gates & illuminated promenade", categories: ["Famous Bridges / Dams", "Rivers, Lakes & Waterfalls", "Viewpoints & Scenic Places"] },
  { name: "Devaraja Heritage Market", deity: "100-Year-Old Royal Spice & Flower Bazaar", city: "Mysuru", rating: "4.7", durationMin: 75, wait: "Market Walk: 1–1.5 hrs", highlight: "Vibrant stalls of Mysore Pak, pure sandalwood, silk & colorful spices", categories: ["Famous Markets & Local Places", "Cultural Places", "Famous City Attractions"] },
  { name: "St. Philomena's Neo-Gothic Cathedral", deity: "Twin 175ft Spired Cathedral", city: "Mysuru", rating: "4.7", durationMin: 45, wait: "Tour: 30–45 mins", highlight: "Towering Neo-Gothic spires, stained glass & underground catacombs", categories: ["Monuments & Landmarks", "Historical & Heritage Places", "Cultural Places"] },
  { name: "Jaganmohan Palace & Art Gallery", deity: "Royal Artworks & Raja Ravi Varma Paintings", city: "Mysuru", rating: "4.7", durationMin: 90, wait: "Gallery: 1–1.5 hrs", highlight: "Magnificent collection of original Ravi Varma oil masterpieces", categories: ["Cultural Places", "Forts & Palaces", "Historical & Heritage Places"] },
  { name: "Balmuri & Edmuri Waterfalls", deity: "Kaveri River Stepped Cascades", city: "Near Mysuru", rating: "4.5", durationMin: 75, wait: "Cascade Viewing: 1 hr", highlight: "Scenic stepped check-dam waterfalls popular for cinema shoots", categories: ["Rivers, Lakes & Waterfalls", "Nature & Forests", "Instagrammable / Photography Spots"] },
  { name: "Ranganathittu Bird Sanctuary", deity: "Kaveri River Boat Safari", city: "Srirangapatna", rating: "4.8", durationMin: 90, wait: "Boating: 1–1.5 hrs", highlight: "Close-up boat safari viewing migratory storks, pelicans & marsh crocodiles", categories: ["Wildlife & National Parks", "Rivers, Lakes & Waterfalls", "Nature & Forests"] },
  { name: "Tipu Sultan's Summer Palace (Dariya Daulat Bagh)", deity: "Teakwood Royal Palace & Mural Gallery", city: "Srirangapatna", rating: "4.7", durationMin: 60, wait: "Tour: 45–60 mins", highlight: "Intricate Persian teakwood carvings & battle mural frescoes", categories: ["Forts & Palaces", "Historical & Heritage Places"] },
  { name: "Sri Ranganathaswamy Temple", deity: "Lord Ranganatha (Adi Ranga)", city: "Srirangapatna", rating: "4.8", durationMin: 75, wait: "30–60 mins", highlight: "Historic island shrine on Kaveri river", categories: ["Temples & Religious Places", "Historical & Heritage Places"] },
  { name: "Sri Srikanteshwara Temple", deity: "Lord Shiva (Dakshina Kashi)", city: "Nanjangud", rating: "4.8", durationMin: 75, wait: "30–60 mins", highlight: "Ancient Kapila river confluence & healing waters", categories: ["Temples & Religious Places", "Historical & Heritage Places"] },

  // --- Coorg (Madikeri / Kushalnagar) ---
  { name: "Abbey Falls & Hanging Bridge", deity: "Cascading Coffee Plantation Waterfall", city: "Madikeri, Coorg", rating: "4.7", durationMin: 75, wait: "Sightseeing: 1 hr", highlight: "70ft roaring waterfall surrounded by lush coffee and spice estates", categories: ["Rivers, Lakes & Waterfalls", "Nature & Forests", "Instagrammable / Photography Spots"] },
  { name: "Raja's Seat Sunset Viewpoint", deity: "Royal Sunset Vista & Musical Fountain", city: "Madikeri, Coorg", rating: "4.7", durationMin: 60, wait: "Sunset: 45–60 mins", highlight: "Panoramic sunset view over Western Ghats mist-covered valleys", categories: ["Viewpoints & Scenic Places", "Hills & Mountains", "Instagrammable / Photography Spots"] },
  { name: "Dubare Elephant Camp & River Rafting", deity: "Kaveri River Elephant Care & Bathing", city: "Kushalnagar, Coorg", rating: "4.7", durationMin: 120, wait: "Activity: 2 hrs", highlight: "River elephant interaction, river crossing boat ride & rafting", categories: ["Wildlife & National Parks", "Rivers, Lakes & Waterfalls", "Nature & Forests"] },
  { name: "Namdroling Monastery (Golden Temple)", deity: "Grand Tibetan Buddhist Monastery", city: "Bylakuppe, Coorg", rating: "4.8", durationMin: 90, wait: "Tour: 1–1.5 hrs", highlight: "40ft gold-plated Buddha statues, ornate Tibetan murals & peace bell", categories: ["Cultural Places", "Temples & Religious Places", "Famous / Must-Visit Places"] },
  { name: "Mandalpatti Peak & Jeep Safari", deity: "Misty High-Altitude Grassland Ridge", city: "Madikeri, Coorg", rating: "4.8", durationMin: 150, wait: "Safari: 2.5 hrs", highlight: "Off-road 4x4 jeep adventure through clouds to 4000ft peak vista", categories: ["Hills & Mountains", "Viewpoints & Scenic Places", "Instagrammable / Photography Spots"] },
  { name: "Madikeri Fort & Palace Museum", deity: "17th Century Elevated Mud & Stone Fort", city: "Madikeri, Coorg", rating: "4.6", durationMin: 60, wait: "Tour: 45–60 mins", highlight: "Historic clock tower, life-size elephant statues & hill views", categories: ["Forts & Palaces", "Historical & Heritage Places", "Monuments & Landmarks"] },
  { name: "Talacauvery & Brahmagiri Hills", deity: "Origin of River Kaveri & Mountain Sanctum", city: "Bhagamandala, Coorg", rating: "4.7", durationMin: 90, wait: "Darshan: 1–1.5 hrs", highlight: "Sacred Kundike holy spring & steps leading to Brahmagiri Peak", categories: ["Rivers, Lakes & Waterfalls", "Hills & Mountains", "Temples & Religious Places"] },
  { name: "Nagarhole National Park (Kabini Safari)", deity: "Tiger & Elephant Safari Reserve", city: "Coorg / Kabini", rating: "4.8", durationMin: 180, wait: "Safari: 3 hrs", highlight: "Thrilling jeep/boat safari spotting leopards, tigers, herds of elephants", categories: ["Wildlife & National Parks", "Nature & Forests"] },
  { name: "Iruppu Falls (Lakshmana Tirtha)", deity: "Dense Forest Mountain Waterfall", city: "South Coorg", rating: "4.7", durationMin: 90, wait: "Trek: 1.5 hrs", highlight: "Scenic forest trail leading to pristine tiered mountain cascades", categories: ["Rivers, Lakes & Waterfalls", "Nature & Forests", "Hills & Mountains"] },
  { name: "Coorg Coffee & Spice Estate Plantation Walk", deity: "Aromatic Arabica & Pepper Plantations", city: "Madikeri, Coorg", rating: "4.7", durationMin: 75, wait: "Walk: 1 hr", highlight: "Guided estate walk tasting fresh coffee beans, cardamom & wild honey", categories: ["Nature & Forests", "Famous Markets & Local Places", "Cultural Places"] },

  // --- Ooty & Nilgiris ---
  { name: "Ooty Botanical Gardens & Glass House", deity: "Historic 55-Acre Victorian Garden", city: "Ooty", rating: "4.7", durationMin: 90, wait: "Walk: 1.5 hrs", highlight: "Lush terraced lawns, 20-million-year-old fossilized tree & exotic flora", categories: ["Nature & Forests", "Famous City Attractions"] },
  { name: "Doddabetta Peak & Telescope Observatory", deity: "Highest Peak in Nilgiris (8650ft)", city: "Ooty", rating: "4.7", durationMin: 75, wait: "Observatory: 1 hr", highlight: "Telescope views spanning the entire Nilgiri mountain range & valleys", categories: ["Hills & Mountains", "Viewpoints & Scenic Places", "Instagrammable / Photography Spots"] },
  { name: "Ooty Lake & Boating Promenade", deity: "Picturesque Mountain Lake & Eucalyptus Groves", city: "Ooty", rating: "4.6", durationMin: 75, wait: "Boating: 1 hr", highlight: "Paddle & motor boating surrounded by towering Nilgiri trees", categories: ["Rivers, Lakes & Waterfalls", "Famous City Attractions"] },
  { name: "Pykara Waterfalls & Pykara Lake", deity: "Sacred Toda Waterfalls & Speed Boating", city: "Near Ooty", rating: "4.7", durationMin: 90, wait: "Boating: 1.5 hrs", highlight: "Pristine tiered waterfalls and tranquil motorboat cruises", categories: ["Rivers, Lakes & Waterfalls", "Nature & Forests", "Instagrammable / Photography Spots"] },
  { name: "Nilgiri Mountain Railway (Heritage Toy Train)", deity: "UNESCO World Heritage Steam Railway", city: "Ooty / Coonoor", rating: "4.8", durationMin: 120, wait: "Train Ride: 1.5–2 hrs", highlight: "Historic vintage steam locomotive passing through mist, bridges & tunnels", categories: ["Historical & Heritage Places", "Famous / Must-Visit Places", "Cultural Places"] },
  { name: "Government Rose Garden", deity: "India's Largest Rose Garden (20,000 Varieties)", city: "Ooty", rating: "4.7", durationMin: 60, wait: "Walk: 1 hr", highlight: "Terraced hillsides blooming with rare hybrid & colorful roses", categories: ["Nature & Forests", "Instagrammable / Photography Spots", "Famous City Attractions"] },
  { name: "Mudumalai National Park & Tiger Reserve", deity: "Nilgiri Biosphere Wildlife Safari", city: "Near Ooty", rating: "4.7", durationMin: 150, wait: "Safari: 2.5 hrs", highlight: "Forest safari spotting wild Asian elephants, gaur, deer & peacocks", categories: ["Wildlife & National Parks", "Nature & Forests"] },
  { name: "Avalanche Lake & Eco-Tourism Sanctuary", deity: "Pristine Trout Lake & Rolling Shola Grasslands", city: "Near Ooty", rating: "4.8", durationMin: 120, wait: "Tour: 2 hrs", highlight: "Untouched forest wonderland, trout fishing & rhododendron blooms", categories: ["Rivers, Lakes & Waterfalls", "Nature & Forests", "Viewpoints & Scenic Places"] },

  // --- Goa & Coastal ---
  { name: "Baga & Calangute Beach Promenade", deity: "Iconic Golden Sand Beach & Water Sports", city: "North Goa", rating: "4.7", durationMin: 120, wait: "Leisure: 2 hrs", highlight: "Parasailing, jet skiing, sunset beach shacks & sea breeze", categories: ["Beaches", "Famous City Attractions", "Instagrammable / Photography Spots"] },
  { name: "Fort Aguada & Historic 1864 Lighthouse", deity: "17th Century Portuguese Sea Bastion", city: "Sinquerim, Goa", rating: "4.7", durationMin: 75, wait: "Tour: 1–1.5 hrs", highlight: "Sweeping Arabian Sea cliffside vistas & preserved freshwater cisterns", categories: ["Forts & Palaces", "Monuments & Landmarks", "Historical & Heritage Places"] },
  { name: "Dudhsagar Waterfalls & Jeep Safari", deity: "India's 5th Highest 4-Tiered Waterfall (1017ft)", city: "Mollem, Goa", rating: "4.8", durationMin: 240, wait: "Safari & Swim: 3–4 hrs", highlight: "Roaring milky-white mountain falls with rail bridge & jungle jeep trail", categories: ["Rivers, Lakes & Waterfalls", "Nature & Forests", "Hills & Mountains"] },
  { name: "Basilica of Bom Jesus & Old Goa Churches", deity: "UNESCO World Heritage Baroque Architecture", city: "Old Goa", rating: "4.8", durationMin: 75, wait: "Tour: 1 hr", highlight: "16th-century gilded altars and sacred relics of St. Francis Xavier", categories: ["Historical & Heritage Places", "Cultural Places", "Monuments & Landmarks"] },
  { name: "Palolem Beach & Butterfly Island", deity: "Crescent-Shaped White Sand Beach & Kayaking", city: "South Goa", rating: "4.8", durationMin: 120, wait: "Relaxation: 2 hrs", highlight: "Scenic palm-fringed tranquil bay with calm waters & dolphin watching", categories: ["Beaches", "Viewpoints & Scenic Places", "Instagrammable / Photography Spots"] },
  { name: "Chapora Fort (Dil Chahta Hai Fort)", deity: "Cliffside Fort overlooking Vagator & Arabian Sea", city: "Vagator, Goa", rating: "4.7", durationMin: 60, wait: "Sunset: 1 hr", highlight: "Iconic cinematic sunset viewpoint over sweeping red cliffs and coastline", categories: ["Forts & Palaces", "Viewpoints & Scenic Places", "Instagrammable / Photography Spots"] },
  { name: "Anjuna Flea Market & Night Bazaar", deity: "Bohemian Craft, Apparel & Music Bazaar", city: "Anjuna, Goa", rating: "4.6", durationMin: 90, wait: "Shopping: 1.5 hrs", highlight: "Eclectic handcrafted jewelry, spices, beachwear & live acoustic music", categories: ["Famous Markets & Local Places", "Cultural Places"] },

  // --- Bengaluru ---
  { name: "Bangalore Palace & Royal Grounds", deity: "Wodeyar Tudor-Style Fortified Palace", city: "Bengaluru", rating: "4.7", durationMin: 120, wait: "Tour: 1.5–2 hrs", highlight: "Tudor-style fortified turrets, royal ballrooms & audio guide tour", categories: ["Forts & Palaces", "Historical & Heritage Places", "Famous / Must-Visit Places"] },
  { name: "Lalbagh Botanical Garden & Glass House", deity: "Heritage Flora & 3000-Million-Yr Peninsular Rock", city: "Bengaluru", rating: "4.8", durationMin: 120, wait: "Garden Walk: 1.5–2 hrs", highlight: "Historic Victorian Glass House, lotus lake & bonsai pavilion", categories: ["Nature & Forests", "Famous City Attractions", "Instagrammable / Photography Spots"] },
  { name: "Bannerghatta Biological Park & Zoo Safari", deity: "Grand Wildlife Park & Butterfly Conservatory", city: "Bengaluru", rating: "4.7", durationMin: 180, wait: "Safari: 2.5–3 hrs", highlight: "Air-conditioned bus safari spotting lions, tigers, bears & butterfly dome", categories: ["Wildlife & National Parks", "Nature & Forests"] },
  { name: "Cubbon Park & Vidhana Soudha Architecture", deity: "300-Acre Green Lung & Neo-Dravidian Statehouse", city: "Bengaluru", rating: "4.7", durationMin: 75, wait: "Sightseeing: 1–1.5 hrs", highlight: "Colonial library walkways & illuminated Neo-Dravidian legislature facade", categories: ["Monuments & Landmarks", "Nature & Forests", "Famous City Attractions"] },
  { name: "Nandi Hills & Sunrise Viewpoint", deity: "Ancient Hill Fortress & Cloud-Sea Sunrise", city: "Near Bengaluru", rating: "4.8", durationMin: 150, wait: "Sunrise Tour: 2 hrs", highlight: "4851ft high mountain sunrise above the clouds, Tipu's Drop & cool breeze", categories: ["Hills & Mountains", "Viewpoints & Scenic Places", "Instagrammable / Photography Spots"] },
  { name: "Commercial Street & Brigade Road Bazaar", deity: "Iconic Shopping Boulevard & Food Street", city: "Bengaluru", rating: "4.6", durationMin: 90, wait: "Shopping: 1.5 hrs", highlight: "Bustling lanes of artisanal clothing, silk sarees & Bangalore cafes", categories: ["Famous Markets & Local Places", "Famous City Attractions"] },
  { name: "Chunchi Waterfalls & Arkavathi Gorge", deity: "Rock-Hewn River Gorge Waterfalls", city: "Near Bengaluru", rating: "4.6", durationMin: 90, wait: "Viewpoint: 1.5 hrs", highlight: "Dramatic rocky river gorge with cascading waterfalls", categories: ["Rivers, Lakes & Waterfalls", "Nature & Forests", "Viewpoints & Scenic Places"] },
  { name: "Manchanabele Dam & Reservoir Vista", deity: "Serene Backwaters & Arkavathi River Dam", city: "Near Bengaluru", rating: "4.5", durationMin: 60, wait: "Lookout: 1 hr", highlight: "Tranquil reservoir lookout surrounded by Savandurga hills", categories: ["Famous Bridges / Dams", "Rivers, Lakes & Waterfalls", "Viewpoints & Scenic Places"] },
  { name: "ISKCON Temple Bangalore", deity: "Sri Sri Radha Krishnachandra", city: "Bengaluru", rating: "4.8", durationMin: 90, wait: "Darshan: 1–1.5 hrs", highlight: "Grand gold-plated dhwaja-stambha on Hare Krishna Hill", categories: ["Temples & Religious Places", "Cultural Places", "Famous / Must-Visit Places"] },
  { name: "Bull Temple (Dodda Basavana Gudi)", deity: "Sacred Nandi Monolith", city: "Bengaluru", rating: "4.7", durationMin: 45, wait: "Darshan: 30–45 mins", highlight: "16th-century monolithic Nandi statue", categories: ["Temples & Religious Places", "Monuments & Landmarks"] },
];

const CURATED_VENUES = {
  tirupati: {
    coffee: { name: "Woodys Highway Restaurant & Cafe", city: "Kolar Highway (NH 75)", rating: "4.6", specialty: "Authentic South Indian Filter Coffee, Crispy Vada & Masala Dosa" },
    breakfast: { name: "Adyar Ananda Bhavan (A2B) Highway Plaza", city: "Mulbagal Highway (NH 75)", rating: "4.5", specialty: "Ghee Podi Idli, Rava Dosa, Hot Filter Coffee" },
    lunch: { name: "Minerva Grand Pure Vegetarian Restaurant", city: "Tirupati", rating: "4.7", specialty: "Grand South Indian Thali, Ghee Sambar Rice & Andhra Thali" },
    dinner: { name: "Bhimas Deluxe Heritage Veg Dining", city: "Tirupati", rating: "4.6", specialty: "Traditional South Indian Thali Meals, Poori Kurma & Sweet Kheer" },
    hotel: { name: "Fortune Select Grand Ridge (ITC Group)", city: "Tirupati", rating: "4.7", specialty: "5-Star Luxury Stay, Veg Dining & Mountain Views" },
  },
  mysuru: {
    coffee: { name: "MTR 1924 Expressway Plaza", city: "Bangalore-Mysore Expressway", rating: "4.7", specialty: "Legendary Rava Idli with Pure Ghee, Masala Dosa & Filter Coffee" },
    breakfast: { name: "Kamat Lokaruchi Heritage Dining", city: "Ramanagara Highway", rating: "4.6", specialty: "Akki Rotti, Jolada Rotti Oota, Filter Coffee" },
    lunch: { name: "Hotel Original Vinayaka Mylari", city: "Mysuru", rating: "4.8", specialty: "World-Famous Butter Mylari Dosa with Fresh White Butter" },
    dinner: { name: "Hotel Dasaprakash Heritage Restaurant", city: "Mysuru", rating: "4.6", specialty: "Traditional Mysuru Royal Thali Meals" },
    hotel: { name: "Grand Mercure Mysuru (Accor)", city: "Mysuru", rating: "4.7", specialty: "Luxury 5-Star Stay overlooking Chamundi Hills" },
  }
};

function getBestCuratedVenue(dest, type) {
  const d = (dest || "").toLowerCase();
  if (d.includes("tirupati") || d.includes("tirumala")) {
    return CURATED_VENUES.tirupati[type] || CURATED_VENUES.tirupati.lunch;
  }
  if (d.includes("mysore") || d.includes("mysuru") || d.includes("mandya") || d.includes("srirangapatna")) {
    return CURATED_VENUES.mysuru[type] || CURATED_VENUES.mysuru.lunch;
  }
  const cleanCity = dest ? dest.split(',')[0].trim() : 'Local';
  return {
    name: `${cleanCity} Traditional ${type === 'hotel' ? 'Comfort Stay & Suites' : type === 'coffee' ? 'Filter Coffee & Refreshment Lounge' : 'Regional Dining Restaurant'}`,
    city: cleanCity,
    rating: "4.7",
    specialty: type === 'hotel' ? 'Comfortable Air-Conditioned Rooms & Parking' : 'Authentic Regional Delicacies & Fresh Food'
  };
}

function getCategoryEmoji(cat) {
  if (!cat) return "⭐";
  if (cat.includes("Temple") || cat.includes("Religious")) return "🛕";
  if (cat.includes("Waterfall") || cat.includes("River") || cat.includes("Lake")) return "🌊";
  if (cat.includes("Viewpoint") || cat.includes("Scenic")) return "🌄";
  if (cat.includes("Hill") || cat.includes("Mountain")) return "⛰️";
  if (cat.includes("Fort") || cat.includes("Palace")) return "🏰";
  if (cat.includes("Forest") || cat.includes("Nature")) return "🌳";
  if (cat.includes("Beach")) return "🏖️";
  if (cat.includes("Wildlife") || cat.includes("National Park")) return "🐘";
  if (cat.includes("Monument") || cat.includes("Landmark")) return "🗿";
  if (cat.includes("Market")) return "🛍️";
  if (cat.includes("Cultural")) return "🎨";
  if (cat.includes("Bridge") || cat.includes("Dam")) return "🌉";
  if (cat.includes("Instagrammable") || cat.includes("Photo")) return "📸";
  if (cat.includes("City")) return "🏙️";
  if (cat.includes("Historical") || cat.includes("Heritage")) return "🏛️";
  return "⭐";
}

function resolveCategoriesForPlace(t, selectedCategories) {
  const placeCats = Array.isArray(t.categories) && t.categories.length
    ? t.categories
    : (t.cat ? [t.cat] : ["Historical & Heritage Places"]);
  if (!selectedCategories || !selectedCategories.length) {
    return { categories: placeCats, match: placeCats[0] };
  }
  const matches = placeCats.filter(c => selectedCategories.includes(c));
  if (matches.length) {
    return { categories: matches, match: matches[0] };
  }
  return { categories: placeCats, match: placeCats[0] };
}

function buildFallbackSmartItinerary({
  destination,
  startLocation,
  places = [],
  durationDays = 1,
  startTime = "08:00",
  preferences = "",
  selectedCategories = [],
  categoryPriorities = {},
  customPreferences = "",
}) {
  const total = Math.max(1, Math.min(Number(durationDays) || 1, 14));
  const destName = destination || "Destination";
  const startName = startLocation || "Home";
  const days = [];

  function cleanCityName(str) {
    if (!str) return "Destination";
    const raw = str.split(',')[0].trim();
    return raw.replace(/\s*\([^)]*\)/g, '').trim() || raw;
  }

  const cleanCity = cleanCityName(destination);
  const text = `${destination} ${preferences} ${customPreferences} ${places.join(" ")}`.toLowerCase();

  // Extract search terms including aliases inside parentheses e.g. "Mangaluru (Mangalore)" -> "mangaluru", "mangalore"
  const parenMatch = destination ? destination.match(/\(([^)]+)\)/) : null;
  const parenAlias = parenMatch ? parenMatch[1].toLowerCase().trim() : "";
  const searchTerms = [cleanCity.toLowerCase(), parenAlias].filter(s => s && s.length >= 3);

  // Step 1: Gather candidate places for this destination from curated library
  let destCandidates = CURATED_ATTRACTIONS.filter(t => {
    const tCity = t.city.toLowerCase();
    return searchTerms.some(st => tCity.includes(st) || text.includes(st));
  });

  // Step 2: Strict Category Filtering
  let pool = [];
  const hasCategoryFilter = Array.isArray(selectedCategories) && selectedCategories.length > 0;
  const templesAllowed = !hasCategoryFilter || selectedCategories.includes("Temples & Religious Places");

  if (hasCategoryFilter) {
    pool = destCandidates.filter(t => {
      const pCats = t.categories || [];
      return pCats.some(c => selectedCategories.includes(c));
    });

    if (!templesAllowed) {
      pool = pool.filter(t => {
        const pCats = t.categories || [];
        return !pCats.includes("Temples & Religious Places");
      });
    }

    // Sort matching pool so "must_visit" categories come first, then "would_like", then "optional"
    pool.sort((a, b) => {
      const pA = (a.categories || []).some(c => (categoryPriorities && categoryPriorities[c]) === "must_visit") ? 0 : 1;
      const pB = (b.categories || []).some(c => (categoryPriorities && categoryPriorities[c]) === "must_visit") ? 0 : 1;
      return pA - pB;
    });
  } else {
    pool = destCandidates.length ? destCandidates : [];
  }

  // Helper to synthesize distinct named attractions per category if needed
  function synthesizeAttraction(city, cat, count) {
    const emojis = {
      "Temples & Religious Places": "🛕", "Rivers, Lakes & Waterfalls": "🌊", "Viewpoints & Scenic Places": "🌄",
      "Hills & Mountains": "⛰️", "Forts & Palaces": "🏰", "Nature & Forests": "🌳", "Beaches": "🏖️",
      "Wildlife & National Parks": "🐘", "Monuments & Landmarks": "🗿", "Famous Markets & Local Places": "🛍️",
      "Cultural Places": "🎨", "Famous Bridges / Dams": "🌉", "Instagrammable / Photography Spots": "📸",
      "Famous City Attractions": "🏙️", "Historical & Heritage Places": "🏛️"
    };
    const c = count || 1;
    if (cat === "Temples & Religious Places") {
      const names = [`${city} Sacred Heritage Shrine`, `${city} Hilltop Spiritual Sanctum`, `${city} Ancient Cultural Temple`];
      return { name: names[(c - 1) % names.length], highlight: "Historic sanctum, spiritual heritage and traditional stone architecture", city: city, rating: "4.8", durationMin: 75, categories: ["Temples & Religious Places", "Historical & Heritage Places"] };
    }
    if (cat === "Beaches") {
      const names = [`${city} Sunset Beach & Coastal Walkway`, `${city} Golden Sands Promenade`, `${city} Coastal Bay & Water Sports Beach`];
      return { name: names[(c - 1) % names.length], highlight: "Golden sand coastline, sea breeze and evening coastal sunset", city: city, rating: "4.8", durationMin: 90, categories: ["Beaches", "Viewpoints & Scenic Places", "Instagrammable / Photography Spots"] };
    }
    if (cat === "Hills & Mountains") {
      const names = [`${city} Misty Mountain Peak & Ridge Lookout`, `${city} Valley Viewpoint & Mountain Trail`, `${city} Cloud-Capped Hilltop Ridge`];
      return { name: names[(c - 1) % names.length], highlight: "High altitude clouds, mountain breeze and valley vistas", city: city, rating: "4.8", durationMin: 120, categories: ["Hills & Mountains", "Viewpoints & Scenic Places"] };
    }
    if (cat === "Rivers, Lakes & Waterfalls") {
      const names = [`${city} Scenic Waterfalls & Cascades`, `${city} Lakefront Promenade & Boating`, `${city} Natural River Gorge & Falls`];
      return { name: names[(c - 1) % names.length], highlight: "Cascading natural waterfalls and serene water promenade", city: city, rating: "4.8", durationMin: 90, categories: ["Rivers, Lakes & Waterfalls", "Nature & Forests"] };
    }
    if (cat === "Viewpoints & Scenic Places") {
      const names = [`${city} Panoramic Sunset Valley Viewpoint`, `${city} Skyline Lookout & Promenade`, `${city} Scenic Landscape Vista`];
      return { name: names[(c - 1) % names.length], highlight: "Breathtaking 360-degree landscape and golden hour sunset vista", city: city, rating: "4.8", durationMin: 60, categories: ["Viewpoints & Scenic Places", "Instagrammable / Photography Spots"] };
    }
    if (cat === "Forts & Palaces") {
      const names = [`${city} Historic Royal Fort & Bastion`, `${city} Heritage Palace & Royal Grounds`, `${city} Ancient Citadel & Courtyard`];
      return { name: names[(c - 1) % names.length], highlight: "Grand royal architecture and fortified courtyard grounds", city: city, rating: "4.8", durationMin: 120, categories: ["Forts & Palaces", "Historical & Heritage Places"] };
    }
    if (cat === "Wildlife & National Parks") {
      const names = [`${city} Wildlife Sanctuary & Safari`, `${city} Nature Reserve & Fauna Park`, `${city} Botanical Bird Sanctuary`];
      return { name: names[(c - 1) % names.length], highlight: "Protected natural fauna habitat and guided flora safari", city: city, rating: "4.8", durationMin: 150, categories: ["Wildlife & National Parks", "Nature & Forests"] };
    }
    if (cat === "Nature & Forests") {
      const names = [`${city} Lush Botanical Gardens & Tree Park`, `${city} Forest Reserve & Canopy Trail`, `${city} Green Valley Eco Park`];
      return { name: names[(c - 1) % names.length], highlight: "Scenic canopy walkways, rare flora and peaceful nature trails", city: city, rating: "4.7", durationMin: 90, categories: ["Nature & Forests", "Rivers, Lakes & Waterfalls"] };
    }
    if (cat === "Famous Markets & Local Places") {
      const names = [`${city} Traditional Artisan Bazaar`, `${city} Heritage Spice & Craft Market`, `${city} Local Food & Souvenir Street`];
      return { name: names[(c - 1) % names.length], highlight: "Vibrant local market with regional delicacies, handicrafts and spices", city: city, rating: "4.7", durationMin: 75, categories: ["Famous Markets & Local Places", "Cultural Places"] };
    }
    return { name: `${city} Iconic Heritage Landmark ${c}`, highlight: "Regional landmark, photography spot and cultural heritage", city: city, rating: "4.8", durationMin: 90, categories: [cat || "Famous / Must-Visit Places"] };
  }

  // Balanced Round-Robin Place Selector (Never repeats any place across days)
  const usedAttractionNames = new Set();
  let slotCounter = 0;

  function getNextAttraction() {
    let targetCategory = null;
    if (hasCategoryFilter && selectedCategories.length > 0) {
      targetCategory = selectedCategories[slotCounter % selectedCategories.length];
    }
    slotCounter++;

    // 1. Try to find an unused matching place in pool
    let chosen = null;
    if (targetCategory) {
      chosen = pool.find(t => !usedAttractionNames.has(t.name) && (t.categories || []).includes(targetCategory));
    }
    if (!chosen) {
      chosen = pool.find(t => !usedAttractionNames.has(t.name));
    }

    // 2. If pool is exhausted or has no unused place, synthesize a unique place
    if (!chosen) {
      const cat = targetCategory || (selectedCategories[0] || "Famous / Must-Visit Places");
      const synthCount = usedAttractionNames.size + 1;
      chosen = synthesizeAttraction(cleanCity, cat, synthCount);
    }

    usedAttractionNames.add(chosen.name);
    return chosen;
  }

  // Realistic highway distance estimation
  let estimatedKm = 145.0;
  const pair = `${startName} ${destName}`.toLowerCase();
  if (pair.includes("mandya") && (pair.includes("tirupati") || pair.includes("tirumala"))) {
    estimatedKm = 345.0;
  } else if (pair.includes("bengaluru") || pair.includes("bangalore")) {
    if (pair.includes("tirupati") || pair.includes("tirumala")) estimatedKm = 250.0;
    else if (pair.includes("mysore") || pair.includes("mysuru")) estimatedKm = 145.0;
    else if (pair.includes("coorg") || pair.includes("madikeri")) estimatedKm = 265.0;
    else if (pair.includes("ooty")) estimatedKm = 280.0;
    else if (pair.includes("chennai")) estimatedKm = 350.0;
    else if (pair.includes("goa")) estimatedKm = 560.0;
    else if (pair.includes("hampi")) estimatedKm = 340.0;
  } else if (pair.includes("mysore") || pair.includes("mysuru")) {
    if (pair.includes("tirupati") || pair.includes("tirumala")) estimatedKm = 385.0;
    else if (pair.includes("coorg") || pair.includes("madikeri")) estimatedKm = 120.0;
    else if (pair.includes("ooty")) estimatedKm = 125.0;
  } else if (pair.includes("chennai") && (pair.includes("tirupati") || pair.includes("tirumala"))) {
    estimatedKm = 135.0;
  }

  const totalDriveMin = Math.round((estimatedKm / 55.0) * 60);

  function parseMinutes(t) {
    const clean = String(t || "").trim().toLowerCase();
    if (!clean) return 480; // 08:00 AM
    const isPm = clean.includes("pm");
    const isAm = clean.includes("am");
    const numStr = clean.replace(/[^0-9:]/g, "");
    const parts = numStr.split(":");
    if (parts.length > 0) {
      let h = parseInt(parts[0], 10) || 8;
      const m = parts.length > 1 ? parseInt(parts[1], 10) || 0 : 0;
      if (isPm && h < 12) h += 12;
      if (isAm && h === 12) h = 0;
      return h * 60 + m;
    }
    return 480;
  }

  function formatMin(totalMin) {
    const norm = totalMin % (24 * 60);
    const h24 = Math.floor(norm / 60);
    const m = norm % 60;
    const ampm = h24 >= 12 ? "PM" : "AM";
    const h12 = h24 === 0 ? 12 : h24 > 12 ? h24 - 12 : h24;
    return `${String(h12).padStart(2, "0")}:${String(m).padStart(2, "0")} ${ampm}`;
  }

  const coffeeHighway = getBestCuratedVenue(destName, "coffee");
  const breakfastVenue = getBestCuratedVenue(destName, "breakfast");
  const lunchVenue = getBestCuratedVenue(destName, "lunch");
  const dinnerVenue = getBestCuratedVenue(destName, "dinner");
  const hotelVenue = getBestCuratedVenue(destName, "hotel");

  for (let d = 1; d <= total; d++) {
    const isFirst = d === 1;
    const isLast = d === total;
    const blocks = [];

    if (isFirst) {
      // --- DAY 1: DEPARTURE & FIRST SIGHTSEEING ---
      let cur = parseMinutes(startTime);

      blocks.push({
        start: formatMin(cur),
        end: formatMin(cur + totalDriveMin),
        type: "travel",
        title: `Drive from ${startName} to ${destName}`,
        place: destName,
        durationMin: totalDriveMin,
        travelMin: totalDriveMin,
        distanceKm: estimatedKm,
        travelMode: "drive",
        reason: "Scenic highway drive with optimal route pacing",
        grounded: true
      });
      cur += totalDriveMin;

      // Arrival Lunch
      blocks.push({
        start: formatMin(cur),
        end: formatMin(cur + 60),
        type: "meal",
        title: `Arrival Lunch at ${lunchVenue.name}`,
        place: `${lunchVenue.name}, ${lunchVenue.city}`,
        durationMin: 60,
        breakType: "lunch",
        reason: `⭐ ${lunchVenue.rating} · ${lunchVenue.specialty}`
      });
      cur += 60;

      // Hotel Check-in
      blocks.push({
        start: formatMin(cur),
        end: formatMin(cur + 45),
        type: "checkin",
        title: `Hotel Check-in at ${hotelVenue.name}`,
        place: `${hotelVenue.name}, ${hotelVenue.city}`,
        durationMin: 45,
        reason: `⭐ ${hotelVenue.rating} · ${hotelVenue.specialty}`
      });
      cur += 45;

      // Afternoon / Evening Stop 1
      const t1 = getNextAttraction();
      const t1Dur = t1.durationMin > 90 ? 75 : t1.durationMin;
      const res1 = resolveCategoriesForPlace(t1, selectedCategories);
      const emoji1 = getCategoryEmoji(res1.match);
      blocks.push({
        start: formatMin(cur),
        end: formatMin(cur + t1Dur),
        type: "activity",
        title: `Visit ${t1.name}`,
        place: `${t1.name}, ${t1.city}`,
        durationMin: t1Dur,
        reason: `${emoji1} ⭐ ${t1.rating || "4.8"} · ${t1.highlight || "Top-rated highlight on route"}`,
        categories: res1.categories,
        whyIncluded: `Matches your selected ${res1.match} preference along the route.`,
      });
      cur += t1Dur;

      // Evening Stop 2
      const t2 = getNextAttraction();
      const t2Dur = t2.durationMin || 90;
      const res2 = resolveCategoriesForPlace(t2, selectedCategories);
      const emoji2 = getCategoryEmoji(res2.match);
      blocks.push({
        start: formatMin(cur),
        end: formatMin(cur + t2Dur),
        type: "activity",
        title: `Explore ${t2.name}`,
        place: `${t2.name}, ${t2.city}`,
        durationMin: t2Dur,
        reason: `${emoji2} ⭐ ${t2.rating || "4.8"} · ${t2.highlight || "Scenic evening experience"}`,
        categories: res2.categories,
        whyIncluded: `Matches your selected ${res2.match} preference along the route.`,
      });
      cur += t2Dur;

      // Traditional Dinner (at or after 07:30 PM)
      if (cur < 1170) cur = 1170; // 07:30 PM minimum
      blocks.push({
        start: formatMin(cur),
        end: formatMin(cur + 60),
        type: "meal",
        title: `Traditional Dinner at ${dinnerVenue.name}`,
        place: `${dinnerVenue.name}, ${dinnerVenue.city}`,
        durationMin: 60,
        breakType: "dinner",
        reason: `⭐ ${dinnerVenue.rating} · ${dinnerVenue.specialty}`
      });
      cur += 60;

      // Night Rest
      blocks.push({
        start: formatMin(cur),
        end: "06:30 AM",
        type: "rest",
        title: `Night Rest at ${hotelVenue.name}`,
        place: `${hotelVenue.name}, ${hotelVenue.city}`,
        durationMin: 480,
        reason: "Peaceful sleep after sightseeing and travel"
      });
    } else if (!isLast) {
      // --- MIDDLE DAY: FULL SIGHTSEEING CIRCUIT ---
      blocks.push({
        start: "08:00 AM",
        end: "09:00 AM",
        type: "meal",
        title: `Morning Breakfast at ${breakfastVenue.name}`,
        place: `${breakfastVenue.name}, ${breakfastVenue.city}`,
        durationMin: 60,
        breakType: "breakfast",
        reason: `⭐ ${breakfastVenue.rating} · ${breakfastVenue.specialty}`
      });

      const t1 = getNextAttraction();
      const t1Duration = t1.durationMin > 180 ? 180 : t1.durationMin;
      const res1 = resolveCategoriesForPlace(t1, selectedCategories);
      const emoji1 = getCategoryEmoji(res1.match);
      blocks.push({
        start: "09:15 AM",
        end: formatMin(555 + t1Duration),
        type: "activity",
        title: `Visit ${t1.name}`,
        place: `${t1.name}, ${t1.city}`,
        durationMin: t1Duration,
        reason: `${emoji1} ⭐ ${t1.rating || "4.8"} · ${t1.highlight || "Iconic regional highlight"}`,
        categories: res1.categories,
        whyIncluded: `Matches your selected ${res1.match} preference along the route.`,
      });

      // Lunch strictly at 12:45 PM
      blocks.push({
        start: "12:45 PM",
        end: "01:45 PM",
        type: "meal",
        title: `Traditional Lunch at ${lunchVenue.name}`,
        place: `${lunchVenue.name}, ${lunchVenue.city}`,
        durationMin: 60,
        breakType: "lunch",
        reason: `⭐ ${lunchVenue.rating} · ${lunchVenue.specialty}`
      });

      const t2 = getNextAttraction();
      const t2Duration = t2.durationMin > 150 ? 150 : t2.durationMin;
      const res2 = resolveCategoriesForPlace(t2, selectedCategories);
      const emoji2 = getCategoryEmoji(res2.match);
      blocks.push({
        start: "02:00 PM",
        end: formatMin(840 + t2Duration),
        type: "activity",
        title: `Explore ${t2.name}`,
        place: `${t2.name}, ${t2.city}`,
        durationMin: t2Duration,
        reason: `${emoji2} ⭐ ${t2.rating || "4.8"} · ${t2.highlight || "Immersive sightseeing stop"}`,
        categories: res2.categories,
        whyIncluded: `Matches your selected ${res2.match} preference along the route.`,
      });

      // Evening Sunset & Tea strictly around 05:45 PM
      blocks.push({
        start: "05:45 PM",
        end: "06:45 PM",
        type: "coffee",
        title: "Evening Sunset & Tea Break",
        place: "Scenic Viewpoint / Promenade",
        durationMin: 60,
        breakType: "coffee",
        reason: "Golden hour views, cool evening breeze and hot tea"
      });

      blocks.push({
        start: "07:30 PM",
        end: "08:30 PM",
        type: "meal",
        title: `Traditional Dinner at ${dinnerVenue.name}`,
        place: `${dinnerVenue.name}, ${dinnerVenue.city}`,
        durationMin: 60,
        breakType: "dinner",
        reason: `⭐ ${dinnerVenue.rating} · ${dinnerVenue.specialty}`
      });

      blocks.push({
        start: "09:30 PM",
        end: "06:30 AM",
        type: "rest",
        title: `Night Rest at ${hotelVenue.name}`,
        place: `${hotelVenue.name}, ${hotelVenue.city}`,
        durationMin: 480,
        reason: "Restful sleep preparing for morning visits"
      });
    } else {
      // --- FINAL DAY: MORNING SIGHTSEEING, LUNCH, CHECK-OUT & RETURN DRIVE ---
      blocks.push({
        start: "08:00 AM",
        end: "09:00 AM",
        type: "meal",
        title: `Morning Breakfast at ${breakfastVenue.name}`,
        place: `${breakfastVenue.name}, ${breakfastVenue.city}`,
        durationMin: 60,
        breakType: "breakfast",
        reason: `⭐ ${breakfastVenue.rating} · ${breakfastVenue.specialty}`
      });

      const t1 = getNextAttraction();
      const t1Duration = t1.durationMin || 60;
      const res1 = resolveCategoriesForPlace(t1, selectedCategories);
      const emoji1 = getCategoryEmoji(res1.match);
      blocks.push({
        start: "09:15 AM",
        end: "10:45 AM",
        type: "activity",
        title: `Explore ${t1.name}`,
        place: `${t1.name}, ${t1.city}`,
        durationMin: t1Duration > 90 ? 90 : t1Duration,
        reason: `${emoji1} ⭐ ${t1.rating || "4.8"} · ${t1.highlight || "Morning sightseeing exploration"}`,
        categories: res1.categories,
        whyIncluded: `Matches your selected ${res1.match} preference along the route.`,
      });

      const t2 = getNextAttraction();
      const t2Duration = t2.durationMin || 90;
      const res2 = resolveCategoriesForPlace(t2, selectedCategories);
      const emoji2 = getCategoryEmoji(res2.match);
      blocks.push({
        start: "11:00 AM",
        end: "12:30 PM",
        type: "activity",
        title: `Visit ${t2.name}`,
        place: `${t2.name}, ${t2.city}`,
        durationMin: t2Duration > 90 ? 90 : t2Duration,
        reason: `${emoji2} ⭐ ${t2.rating || "4.8"} · ${t2.highlight || "Historic sight on return circuit"}`,
        categories: res2.categories,
        whyIncluded: `Matches your selected ${res2.match} preference along the route.`,
      });

      // Lunch strictly at 12:30 PM
      blocks.push({
        start: "12:30 PM",
        end: "01:30 PM",
        type: "meal",
        title: `Traditional Farewell Lunch at ${lunchVenue.name}`,
        place: `${lunchVenue.name}, ${lunchVenue.city}`,
        durationMin: 60,
        breakType: "lunch",
        reason: `⭐ ${lunchVenue.rating} · ${lunchVenue.specialty}`
      });

      // Hotel Check-out at 01:30 PM
      blocks.push({
        start: "01:30 PM",
        end: "02:00 PM",
        type: "checkout",
        title: `Hotel Check-out from ${hotelVenue.name}`,
        place: `${hotelVenue.name}, ${hotelVenue.city}`,
        durationMin: 30,
        reason: "Settle bills, load prasadam & luggage into vehicle"
      });

      // Return Drive
      let cur = 840; // 02:00 PM
      if (totalDriveMin > 180) {
        const ret1 = Math.round(totalDriveMin * 0.5);
        const ret2 = totalDriveMin - ret1;
        const dist1 = Math.round(estimatedKm * 0.5);
        const dist2 = Math.round(estimatedKm - dist1);

        blocks.push({
          start: formatMin(cur),
          end: formatMin(cur + ret1),
          type: "travel",
          title: "Return Drive (Highway Leg 1)",
          place: "National Highway",
          durationMin: ret1,
          travelMin: ret1,
          distanceKm: dist1,
          travelMode: "drive",
          reason: "Smooth afternoon highway cruising returning home"
        });
        cur += ret1;

        blocks.push({
          start: formatMin(cur),
          end: formatMin(cur + 45),
          type: "coffee",
          title: `Sunset Highway Coffee Break at ${coffeeHighway.name}`,
          place: `${coffeeHighway.name}, ${coffeeHighway.city}`,
          durationMin: 45,
          breakType: "coffee",
          reason: `⭐ ${coffeeHighway.rating} · ${coffeeHighway.specialty}`
        });
        cur += 45;

        blocks.push({
          start: formatMin(cur),
          end: formatMin(cur + ret2),
          type: "return",
          title: `Return Drive back to ${startName}`,
          place: startName,
          durationMin: ret2,
          travelMin: ret2,
          distanceKm: dist2,
          travelMode: "drive",
          reason: `Final evening highway cruise arriving safely back at ${startName}`
        });
        cur += ret2;
      } else {
        blocks.push({
          start: formatMin(cur),
          end: formatMin(cur + totalDriveMin),
          type: "return",
          title: `Return Drive back to ${startName}`,
          place: startName,
          durationMin: totalDriveMin,
          travelMin: totalDriveMin,
          distanceKm: estimatedKm,
          travelMode: "drive",
          reason: "Smooth evening highway cruise returning home"
        });
        cur += totalDriveMin;
      }

      blocks.push({
        start: formatMin(cur),
        end: formatMin(cur + 45),
        type: "meal",
        title: `Dinner Arrival at ${startName}`,
        place: "Local Restaurant / Home Diner",
        durationMin: 45,
        breakType: "dinner",
        reason: "Relaxing dinner marking the auspicious conclusion of pilgrimage"
      });
    }

    days.push({
      day: d,
      date: `Day ${d}`,
      title: isFirst
        ? `Arrival & Highlights of ${destName}`
        : isLast
        ? `Farewell ${destName} & Return Journey`
        : `Full Day Exploration of ${destName}`,
      blocks
    });
  }

  return days;
}

module.exports = { recommendStops, searchPlaces, travelOptions, ask, buildItinerary, smartItinerary, listModels, AiConfigError, PROVIDER, ACTIVE_MODEL };

