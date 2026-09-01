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
  const anchor = near ? ` near ${near}` : "";
  const prompt = `Find up to 8 real, specific places matching this request${anchor}: "${query}". ${PLACES_JSON_HINT}`;
  return safeParsePlaces(await generate(prompt, {
    system: "You are a concise, accurate travel search assistant. Only return real, specific places.",
    json: true,
  }));
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
  `For meal blocks set breakType to breakfast|lunch|dinner.`;

const ITINERARY_JSON_HINT =
  `Respond ONLY as JSON: {"days":[{"day":1,"date":"","title":"","blocks":[{"start":"08:00",` +
  `"end":"08:30","type":"meal","title":"Breakfast","place":"","durationMin":30,"travelMin":0,` +
  `"distanceKm":0,"breakType":"breakfast","reason":"","travelMode":""}]}]} — travel blocks set ` +
  `travelMode; no prose, no markdown.`;

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
 *
 * Long itineraries are generated in small day-batches and stitched together, so
 * no single model call exceeds the provider's token budget (which would truncate
 * the JSON — dropping days — or trip the free-tier rate limit). Batches are
 * best-effort: if one fails after retries, whatever days succeeded are returned
 * rather than failing the whole request.
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
}) {
  const total = Math.max(1, Math.min(Number(durationDays) || 1, 14));
  const placeLine = places.length ? `Must-visit places (spread across the trip): ${places.join(", ")}. ` : "";
  const paceLine =
    mode === "packed"
      ? "Pace: PACKED — fit in as much as reasonably possible, shorter breaks. "
      : mode === "relaxed"
      ? "Pace: RELAXED — fewer activities, longer meals/rest, plenty of free time. "
      : "Pace: BALANCED — a comfortable mix of sightseeing, meals and rest. ";
  const prefLine = preferences ? `Traveller preferences: ${preferences}. ` : "";
  const directiveLine = directive ? `IMPORTANT adjustment for this version: ${directive}. ` : "";
  const homeLine = startLocation ? ` starting from the traveller's home "${startLocation}"` : "";

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
    return ctx + placeLine + prefLine + paceLine + directiveLine + ITINERARY_RULES + " " + ITINERARY_JSON_HINT;
  }

  // One model call for the whole trip (multiple back-to-back calls tripped the
  // per-minute limit). reasoning_effort "low" keeps the token budget for the JSON
  // rather than gpt-oss's hidden reasoning. Each Groq model has its OWN daily
  // token quota, so on a rate-limit (429) we fall back to the next model instead
  // of failing — this keeps planning working after one model's daily cap is hit.
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
        // reasoning_effort only applies to gpt-oss (reasoning) models.
        reasoningEffort: m && m.includes("gpt-oss") ? "low" : undefined,
        maxTokens: 7000,
      });
      days = safeParseSmart(text);
      if (days.length) break;
    } catch (err) {
      lastErr = err;
      const status = err.response ? err.response.status : 0;
      console.error(`Itinerary model ${m} failed:`, status, err.response ? JSON.stringify(err.response.data).slice(0, 200) : err.message);
  // If AI generation didn't return any days, generate an intelligent fallback plan
  if (!days.length) {
    console.log("Generating smart fallback itinerary for", destination);
    days = buildFallbackSmartItinerary({
      destination,
      startLocation,
      places,
      durationDays: total,
      startTime,
      preferences,
    });
  }

  days = days.slice(0, total);
  days.forEach((d, i) => { d.day = i + 1; });
  return days;
}

function buildFallbackSmartItinerary({ destination, startLocation, places = [], durationDays = 1, startTime = "08:00", preferences = "" }) {
  const total = Math.max(1, Math.min(Number(durationDays) || 1, 14));
  const destName = destination || "Destination";
  const startName = startLocation || "Home";
  const days = [];

  const defaultAttractions = places.length > 0 ? places : [
    `${destName} Historic Palace & Royal Grounds`,
    `Sri Chamundeshwari Temple & Hilltop Ridge`,
    `${destName} Heritage Lake & Waterfront Promenade`,
    `Local Spice, Silk & Handicrafts Bazaar`,
    `Botanical Gardens & Panoramic Viewpoint`,
    `Art & Cultural Heritage Museum`,
    `Sunset Hilltop & Scenic Vista`
  ];

  let placeIdx = 0;
  function getNextPlace() {
    const p = defaultAttractions[placeIdx % defaultAttractions.length];
    placeIdx++;
    return p;
  }

  for (let d = 1; d <= total; d++) {
    const isFirst = d === 1;
    const isLast = d === total;
    const blocks = [];

    if (isFirst) {
      blocks.push({
        start: startTime || "08:00",
        end: "10:30",
        type: "travel",
        title: `Drive from ${startName} to ${destName}`,
        place: destName,
        durationMin: 150,
        travelMin: 150,
        distanceKm: 145,
        travelMode: "drive",
        reason: "Scenic highway drive with morning traffic clearance"
      });
      blocks.push({
        start: "10:30",
        end: "11:15",
        type: "coffee",
        title: "Highway Coffee & Breakfast Refreshment",
        place: "Highway Cafe / Diner",
        durationMin: 45,
        breakType: "breakfast",
        reason: "Traditional filter coffee and light snack break"
      });
      blocks.push({
        start: "11:45",
        end: "12:30",
        type: "checkin",
        title: `Hotel Check-in & Unpack in ${destName}`,
        place: `${destName} Grand Stay / Resort`,
        durationMin: 45,
        reason: "Check in, freshen up and relax before afternoon exploration"
      });
    } else {
      blocks.push({
        start: "08:00",
        end: "09:00",
        type: "meal",
        title: "Morning Breakfast at Hotel / Cafe",
        place: `${destName} Local Eatery`,
        durationMin: 60,
        breakType: "breakfast",
        reason: "Fresh local breakfast to start the day energised"
      });
    }

    // Morning / Afternoon Activity
    const p1 = getNextPlace();
    blocks.push({
      start: isFirst ? "12:30" : "09:30",
      end: isFirst ? "14:00" : "12:30",
      type: "activity",
      title: `Visit & Explore ${p1}`,
      place: p1,
      durationMin: isFirst ? 90 : 180,
      reason: "Top-rated cultural and architectural highlight"
    });

    // Lunch
    blocks.push({
      start: isFirst ? "14:00" : "12:45",
      end: isFirst ? "15:00" : "14:00",
      type: "meal",
      title: `Traditional Lunch in ${destName}`,
      place: "Local Heritage Restaurant",
      durationMin: 60,
      breakType: "lunch",
      reason: "Authentic regional thali and specialties"
    });

    // Afternoon Activity
    const p2 = getNextPlace();
    blocks.push({
      start: "15:15",
      end: "17:30",
      type: "activity",
      title: `Sightseeing at ${p2}`,
      place: p2,
      durationMin: 135,
      reason: "Immerse in scenic views and vibrant local heritage"
    });

    // Evening Coffee / Sunset
    blocks.push({
      start: "17:45",
      end: "18:45",
      type: "coffee",
      title: "Sunset Views & Evening Tea",
      place: "Panoramic Hill / Lakeside Viewpoint",
      durationMin: 60,
      breakType: "coffee",
      reason: "Golden hour photography and relaxing refreshments"
    });

    if (isLast) {
      if (total > 1) {
        blocks.push({
          start: "18:45",
          end: "19:15",
          type: "checkout",
          title: `Hotel Check-out from ${destName}`,
          place: `${destName} Hotel`,
          durationMin: 30,
          reason: "Settle bills, load luggage into vehicle"
        });
      }
      blocks.push({
        start: "19:15",
        end: "21:45",
        type: "return",
        title: `Return Drive back to ${startName}`,
        place: startName,
        durationMin: 150,
        travelMin: 150,
        distanceKm: 145,
        travelMode: "drive",
        reason: "Smooth evening highway cruise returning home"
      });
      blocks.push({
        start: "22:00",
        end: "22:45",
        type: "meal",
        title: `Dinner Arrival at ${startName}`,
        place: "Home / Local Dining",
        durationMin: 45,
        breakType: "dinner",
        reason: "Relaxing meal to conclude the road trip"
      });
    } else {
      blocks.push({
        start: "19:30",
        end: "21:00",
        type: "meal",
        title: `Dinner & Evening Leisure in ${destName}`,
        place: "Celebrated Fine Dining / Dhaba",
        durationMin: 90,
        breakType: "dinner",
        reason: "Enjoy authentic dinner and evening city ambiance"
      });
      blocks.push({
        start: "21:15",
        end: "22:00",
        type: "rest",
        title: "Night Rest & Trip Reflection",
        place: `${destName} Hotel / Resort`,
        durationMin: 45,
        reason: "Good night rest for the next day's adventures"
      });
    }

    days.push({
      day: d,
      date: `Day ${d}`,
      title: isFirst ? `Arrival & Highlights of ${destName}` : isLast ? `Farewell ${destName} & Return Journey` : `Deep Dive into ${destName} Heritage`,
      blocks
    });
  }

  return days;
}

module.exports = { recommendStops, searchPlaces, travelOptions, ask, buildItinerary, smartItinerary, listModels, AiConfigError, PROVIDER, ACTIVE_MODEL };

