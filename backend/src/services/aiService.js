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
      preferences,
    });
  }

  days = days.slice(0, total);
  days.forEach((d, i) => { d.day = i + 1; });
  return days;
}

const CURATED_TEMPLES = [
  // --- Tirupati / Tirumala ---
  { name: "Shri Varaha Swamy Temple", deity: "Lord Adi Varaha Swamy", city: "Tirumala, Tirupati", rating: "4.8", durationMin: 60, wait: "30–60 mins", highlight: "Holy Swami Pushkarini bank traditional first darshan" },
  { name: "Sri Venkateswara Swamy Temple", deity: "Lord Venkateswara (Balaji)", city: "Tirumala, Tirupati", rating: "4.8", durationMin: 240, wait: "SED (₹300): 3–4 hrs · SSD Slotted: 4–6 hrs · Free: 8–12 hrs · VIP: ~1 hr", highlight: "Golden Ananda Nilayam vimana & Laddu prasadam" },
  { name: "Sri Bedi Anjaneya Swamy Temple", deity: "Lord Hanuman", city: "Tirumala, Tirupati", rating: "4.8", durationMin: 45, wait: "20–45 mins", highlight: "Directly opposite main Mahadwaram gopuram" },
  { name: "Sri Padmavathi Ammavari Temple", deity: "Goddess Padmavathi (Alamelu Manga)", city: "Tiruchanur, Tirupati", rating: "4.7", durationMin: 90, wait: "Special: 1–2 hrs · General: 2–3 hrs", highlight: "Sacred Padma Sarovaram tank blessings" },
  { name: "Sri Kalyana Venkateswara Swamy Temple", deity: "Lord Kalyana Venkateswara", city: "Srinivasa Mangapuram", rating: "4.7", durationMin: 60, wait: "30–60 mins", highlight: "Divine wedding post-marriage stay site" },
  { name: "Sri Kapileswara Swamy Temple & Kapila Theertham", deity: "Lord Shiva", city: "Tirupati", rating: "4.7", durationMin: 60, wait: "30–60 mins", highlight: "Sacred mountain waterfall & spring" },
  { name: "Sri Govindaraja Swamy Temple", deity: "Lord Govindaraja Swamy", city: "Tirupati", rating: "4.7", durationMin: 75, wait: "45–90 mins", highlight: "Towering 12th-century Raja Gopuram" },
  { name: "Srikalahasti Temple", deity: "Lord Shiva (Kalahasteeswara)", city: "Srikalahasti", rating: "4.7", durationMin: 150, wait: "Rahu-Ketu: 2–3 hrs · General: 1–2 hrs", highlight: "Pancha Bhoota Vayu Lingam & Rahu-Ketu puja" },
  { name: "Kanipakam Vinayaka Temple", deity: "Lord Varasidhi Vinayaka", city: "Kanipakam", rating: "4.7", durationMin: 90, wait: "Special: 1–1.5 hrs · General: 2–3 hrs", highlight: "Swayambhu growing Ganesha in water well" },
  // --- Mysuru ---
  { name: "Mysore Palace (Amba Vilas)", deity: "Wodeyar Royal Heritage & Durbar", city: "Mysuru", rating: "4.8", durationMin: 150, wait: "Palace Tour: 2–3 hrs", highlight: "Golden Throne, stained glass Kalyana Mantapa ceiling" },
  { name: "Sri Chamundeshwari Temple", deity: "Goddess Chamundeshwari", city: "Chamundi Hills, Mysuru", rating: "4.8", durationMin: 90, wait: "Special: 45–75 mins · General: 1.5–2.5 hrs", highlight: "Hilltop Shakti Peetha & monolithic Nandi" },
  { name: "Brindavan Gardens & Musical Fountain", deity: "Terraced Gardens & Kaveri Waterway", city: "Mysuru", rating: "4.7", durationMin: 120, wait: "Garden & Light Show: 2–2.5 hrs", highlight: "Terraced garden walkways & synchronized musical fountain" },
  { name: "Sri Ranganathaswamy Temple", deity: "Lord Ranganatha (Adi Ranga)", city: "Srirangapatna", rating: "4.8", durationMin: 75, wait: "30–60 mins", highlight: "Historic island shrine on Kaveri river" },
  { name: "Sri Srikanteshwara Temple", deity: "Lord Shiva (Dakshina Kashi)", city: "Nanjangud", rating: "4.8", durationMin: 75, wait: "30–60 mins", highlight: "Ancient Kapila river confluence & healing waters" },
  // --- Bengaluru ---
  { name: "ISKCON Temple Bangalore", deity: "Sri Sri Radha Krishnachandra", city: "Bengaluru", rating: "4.8", durationMin: 90, wait: "Darshan: 1–1.5 hrs", highlight: "Grand gold-plated dhwaja-stambha on Hare Krishna Hill" },
  { name: "Bull Temple (Dodda Basavana Gudi)", deity: "Sacred Nandi Monolith", city: "Bengaluru", rating: "4.7", durationMin: 45, wait: "Darshan: 30–45 mins", highlight: "16th-century monolithic Nandi statue" },
  { name: "Bangalore Palace & Royal Grounds", deity: "Wodeyar Royal Heritage", city: "Bengaluru", rating: "4.7", durationMin: 120, wait: "Tour: 1.5–2 hrs", highlight: "Tudor-style fortified turrets and royal galleries" },
  { name: "Lalbagh Botanical Garden & Glass House", deity: "Heritage Flora & 3000-Million-Yr Rock", city: "Bengaluru", rating: "4.8", durationMin: 120, wait: "Garden Walk: 1.5–2.5 hrs", highlight: "Historic Glass House & Kempegowda watchtower" },
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
  if (d.includes("mysore") || d.includes("mysuru") || d.includes("mandya")) {
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

function buildFallbackSmartItinerary({ destination, startLocation, places = [], durationDays = 1, startTime = "08:00", preferences = "" }) {
  const total = Math.max(1, Math.min(Number(durationDays) || 1, 14));
  const destName = destination || "Destination";
  const startName = startLocation || "Home";
  const days = [];

  const text = `${destination} ${preferences} ${places.join(" ")}`.toLowerCase();
  let pool = [];
  if (text.includes("tirupati") || text.includes("tirumala") || text.includes("balaji") || text.includes("venkateswara")) {
    pool = CURATED_TEMPLES.filter(t => t.city.includes("Tirupati") || t.city.includes("Tirumala") || t.city.includes("Srikalahasti") || t.city.includes("Kanipakam"));
  } else if (text.includes("mysore") || text.includes("mysuru") || text.includes("srirangapatna") || text.includes("mandya")) {
    pool = CURATED_TEMPLES.filter(t => t.city.includes("Mysuru") || t.city.includes("Srirangapatna") || t.city.includes("Nanjangud"));
  } else if (text.includes("bengaluru") || text.includes("bangalore") || text.includes("mathikere")) {
    pool = CURATED_TEMPLES.filter(t => t.city.includes("Bengaluru"));
  }

  if (!pool.length) {
    const cleanCity = destination ? destination.split(',')[0].trim() : "Destination";
    pool = [
      { name: `${cleanCity} Historic Heritage Monument & Palace`, deity: "Architectural Heritage & Grounds", city: cleanCity, rating: "4.8", durationMin: 120, wait: "Tour: 1.5–2.5 hrs", highlight: "Iconic royal architecture and scenic courtyard grounds" },
      { name: `${cleanCity} Sacred Spiritual Sanctum`, deity: "Presiding Deity & Holy Sanctum", city: cleanCity, rating: "4.8", durationMin: 75, wait: "Darshan: 1–1.5 hrs", highlight: "Historic cultural sanctum and traditional aarti" },
      { name: `${cleanCity} Waterfront Promenade & Botanical Gardens`, deity: "Scenic Nature & Lakeside Vista", city: cleanCity, rating: "4.7", durationMin: 75, wait: "Leisure: 1–1.5 hrs", highlight: "Lush botanical walkways and sunset fountain viewing" },
      { name: `${cleanCity} Panoramic Hilltop Vista`, deity: "360° Panoramic Landscape", city: cleanCity, rating: "4.8", durationMin: 60, wait: "Sightseeing: 45–60 mins", highlight: "Golden hour photography and panoramic valley views" },
      { name: `${cleanCity} Traditional Artisan & Food Bazaar`, deity: "Regional Crafts & Specialties", city: cleanCity, rating: "4.6", durationMin: 90, wait: "Shopping: 1–2 hrs", highlight: "Authentic local delicacies and handcrafted souvenirs" },
    ];
  }

  let templeIdx = 0;
  function getNextTemple() {
    const t = pool[templeIdx % pool.length];
    templeIdx++;
    return t;
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
      // --- DAY 1: OUTWARD TRAVEL & EVENING SIGHTSEEING/DARSHAN ---
      const startMin = parseMinutes(startTime);
      let cur = startMin;

      if (totalDriveMin > 180) {
        // Long drive (>3 hours): Split with midway breakfast/coffee
        const leg1 = Math.round(totalDriveMin * 0.45);
        const leg2 = totalDriveMin - leg1;
        const dist1 = Math.round(estimatedKm * 0.45);
        const dist2 = Math.round(estimatedKm - dist1);

        blocks.push({
          start: formatMin(cur),
          end: formatMin(cur + leg1),
          type: "travel",
          title: `Drive from ${startName} (Highway Leg 1)`,
          place: "National Highway",
          durationMin: leg1,
          travelMin: leg1,
          distanceKm: dist1,
          travelMode: "drive",
          reason: "Morning highway drive with smooth cruising"
        });
        cur += leg1;

        blocks.push({
          start: formatMin(cur),
          end: formatMin(cur + 45),
          type: "coffee",
          title: `Highway Coffee & Breakfast at ${coffeeHighway.name}`,
          place: `${coffeeHighway.name}, ${coffeeHighway.city}`,
          durationMin: 45,
          breakType: "breakfast",
          reason: `⭐ ${coffeeHighway.rating} · ${coffeeHighway.specialty}`
        });
        cur += 45;

        blocks.push({
          start: formatMin(cur),
          end: formatMin(cur + leg2),
          type: "travel",
          title: `Drive to ${destName} (Highway Leg 2)`,
          place: destName,
          durationMin: leg2,
          travelMin: leg2,
          distanceKm: dist2,
          travelMode: "drive",
          reason: `Scenic approach drive arriving in ${destName}`
        });
        cur += leg2;
      } else {
        // Short drive (<= 3 hours)
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
          reason: "Smooth morning drive along highway with traffic clearance"
        });
        cur += totalDriveMin;
      }

      // Arrival Lunch
      blocks.push({
        start: formatMin(cur),
        end: formatMin(cur + 60),
        type: "meal",
        title: `Traditional Arrival Lunch at ${lunchVenue.name}`,
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

      // If arrived early before 03:00 PM, allow a preliminary shrine visit
      if (cur < 900) {
        const tPrelim = getNextTemple();
        const tPrelimDur = tPrelim.durationMin > 90 ? 75 : tPrelim.durationMin;
        blocks.push({
          start: formatMin(cur),
          end: formatMin(cur + tPrelimDur),
          type: "activity",
          title: `Darshan at ${tPrelim.name}`,
          place: `${tPrelim.name}, ${tPrelim.city}`,
          durationMin: tPrelimDur,
          reason: `🛕 Deity: ${tPrelim.deity} · ⭐ ${tPrelim.rating} · ${tPrelim.highlight}`
        });
        cur += tPrelimDur;
      }

      // Grand Evening Temple / Main Attraction
      const tMain = getNextTemple();
      const tDuration = tMain.durationMin || 90;
      const tWait = tMain.wait ? ` · ⏳ Darshan Wait: ${tMain.wait}` : "";
      blocks.push({
        start: formatMin(cur),
        end: formatMin(cur + tDuration),
        type: "activity",
        title: `Grand Darshan at ${tMain.name}`,
        place: `${tMain.name}, ${tMain.city}`,
        durationMin: tDuration,
        reason: `🛕 Deity: ${tMain.deity} · ⭐ ${tMain.rating}${tWait} · ${tMain.highlight}`
      });
      cur += tDuration;

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
        reason: "Peaceful sleep after sacred darshan and travel"
      });
    } else if (!isLast) {
      // --- MIDDLE DAY: FULL SIGHTSEEING & PILGRIMAGE CIRCUIT ---
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

      const t1 = getNextTemple();
      const t1Duration = t1.durationMin > 180 ? 180 : t1.durationMin;
      const t1Wait = t1.wait ? ` · ⏳ Darshan Wait: ${t1.wait}` : "";
      blocks.push({
        start: "09:15 AM",
        end: formatMin(555 + t1Duration),
        type: "activity",
        title: `Darshan at ${t1.name}`,
        place: `${t1.name}, ${t1.city}`,
        durationMin: t1Duration,
        reason: `🛕 Deity: ${t1.deity} · ⭐ ${t1.rating}${t1Wait} · ${t1.highlight}`
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

      const t2 = getNextTemple();
      const t2Duration = t2.durationMin > 150 ? 150 : t2.durationMin;
      const t2Wait = t2.wait ? ` · ⏳ Darshan Wait: ${t2.wait}` : "";
      blocks.push({
        start: "02:00 PM",
        end: formatMin(840 + t2Duration),
        type: "activity",
        title: `Visit & Darshan at ${t2.name}`,
        place: `${t2.name}, ${t2.city}`,
        durationMin: t2Duration,
        reason: `🛕 Deity: ${t2.deity} · ⭐ ${t2.rating}${t2Wait} · ${t2.highlight}`
      });

      // Evening Sunset & Tea strictly around 05:45 PM
      blocks.push({
        start: "05:45 PM",
        end: "06:45 PM",
        type: "coffee",
        title: "Evening Sunset & Tea Break",
        place: "Scenic Viewpoint / Temple Promenade",
        durationMin: 60,
        breakType: "coffee",
        reason: "Golden hour views, cool evening breeze & hot tea"
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
      // --- FINAL DAY: MORNING SHRINES, LUNCH, CHECK-OUT & RETURN DRIVE ---
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

      const t1 = getNextTemple();
      const t1Duration = t1.durationMin || 60;
      const t1Wait = t1.wait ? ` · ⏳ Darshan Wait: ${t1.wait}` : "";
      blocks.push({
        start: "09:15 AM",
        end: "10:45 AM",
        type: "activity",
        title: `Darshan at ${t1.name}`,
        place: `${t1.name}, ${t1.city}`,
        durationMin: t1Duration > 90 ? 90 : t1Duration,
        reason: `🛕 Deity: ${t1.deity} · ⭐ ${t1.rating}${t1Wait} · ${t1.highlight}`
      });

      const t2 = getNextTemple();
      const t2Duration = t2.durationMin || 90;
      const t2Wait = t2.wait ? ` · ⏳ Darshan Wait: ${t2.wait}` : "";
      blocks.push({
        start: "11:00 AM",
        end: "12:30 PM",
        type: "activity",
        title: `Visit & Darshan at ${t2.name}`,
        place: `${t2.name}, ${t2.city}`,
        durationMin: t2Duration > 90 ? 90 : t2Duration,
        reason: `🛕 Deity: ${t2.deity} · ⭐ ${t2.rating}${t2Wait} · ${t2.highlight}`
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

