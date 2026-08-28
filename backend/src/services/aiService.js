const axios = require("axios");

// Provider-agnostic AI. Set AI_PROVIDER = gemini | groq | openrouter to force one,
// otherwise auto-detect from whichever key is present (Groq/OpenRouter preferred —
// they need no billing, unlike Gemini's billing-gated free tier).
const PROVIDER = (
  process.env.AI_PROVIDER ||
  (process.env.GROQ_API_KEY ? "groq" : process.env.OPENROUTER_API_KEY ? "openrouter" : "gemini")
).toLowerCase();

const GEMINI_KEY = process.env.GEMINI_API_KEY || process.env.GOOGLE_API_KEY;
const GEMINI_MODEL = process.env.GEMINI_MODEL || "gemini-2.0-flash";
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

  const BATCH = 2; // days per model call — keeps each response well under the token cap
  const out = [];
  for (let from = 1; from <= total; from += BATCH) {
    const to = Math.min(from + BATCH - 1, total);
    const count = to - from + 1;
    let batch = [];
    try {
      const text = await generateWithRetry(batchPrompt(from, to), {
        system: ITINERARY_SYSTEM,
        json: true,
        model: PROVIDER === "groq" ? "openai/gpt-oss-120b" : undefined,
        // ~2000 output tokens/day + headroom, capped to stay under the free-tier
        // per-minute budget on any single call.
        maxTokens: Math.min(6000, count * 2000 + 1000),
      });
      batch = safeParseSmart(text);
    } catch (err) {
      console.error(`Itinerary batch days ${from}-${to} failed:`, err.message);
      break; // return the days gathered so far rather than failing the request
    }
    if (!batch.length) break;
    out.push(...batch);
    if (to < total) await sleep(400); // gentle spacing between calls
  }

  // Renumber sequentially and cap to the requested length.
  const days = out.slice(0, total);
  days.forEach((d, i) => { d.day = i + 1; });
  return days;
}

module.exports = { recommendStops, searchPlaces, ask, buildItinerary, smartItinerary, listModels, AiConfigError, PROVIDER, ACTIVE_MODEL };
