const axios = require("axios");

// Google Gemini (free tier). Set GEMINI_API_KEY in the backend environment.
// Model is configurable; defaults to a fast, free-tier model.
const GEMINI_KEY = process.env.GEMINI_API_KEY || process.env.GOOGLE_API_KEY;
const GEMINI_MODEL = process.env.GEMINI_MODEL || "gemini-1.5-flash";
const BASE = "https://generativelanguage.googleapis.com/v1beta/models";

class AiConfigError extends Error {}

/**
 * Low-level Gemini call. Returns the model's text output.
 * @param {string} prompt
 * @param {{system?:string, json?:boolean, schema?:object}} [opts]
 */
async function generate(prompt, opts = {}) {
  if (!GEMINI_KEY) {
    throw new AiConfigError("GEMINI_API_KEY is not set on the server");
  }
  const url = `${BASE}/${encodeURIComponent(GEMINI_MODEL)}:generateContent?key=${GEMINI_KEY}`;
  const body = {
    contents: [{ role: "user", parts: [{ text: prompt }] }],
    generationConfig: { temperature: 0.7 },
  };
  if (opts.system) body.systemInstruction = { parts: [{ text: opts.system }] };
  if (opts.json) {
    body.generationConfig.responseMimeType = "application/json";
    if (opts.schema) body.generationConfig.responseSchema = opts.schema;
  }

  const res = await axios.post(url, body, {
    headers: { "Content-Type": "application/json" },
    timeout: 30000,
  });

  const parts = res.data?.candidates?.[0]?.content?.parts || [];
  return parts.map((p) => p.text || "").join("").trim();
}

// Gemini responseSchema for a list of places.
const PLACES_SCHEMA = {
  type: "ARRAY",
  items: {
    type: "OBJECT",
    properties: {
      name: { type: "STRING" },
      area: { type: "STRING" },
      why: { type: "STRING" },
    },
    required: ["name", "why"],
  },
};

function safeParsePlaces(text) {
  try {
    const data = JSON.parse(text);
    if (Array.isArray(data)) {
      return data
        .filter((p) => p && p.name)
        .slice(0, 12)
        .map((p) => ({ name: String(p.name), area: p.area ? String(p.area) : "", why: p.why ? String(p.why) : "" }));
    }
  } catch (_) {/* fall through */}
  return [];
}

/** Recommend notable stops along a route. */
async function recommendStops({ start, end, waypoints = [] }) {
  const via = waypoints.length ? ` via ${waypoints.join(", ")}` : "";
  const prompt =
    `Suggest up to 8 genuinely notable, popular places to stop and visit on a road trip ` +
    `from "${start}" to "${end}"${via}. Prefer well-known attractions, viewpoints, temples, ` +
    `forts, waterfalls, lakes and towns that are roughly on or near the route. ` +
    `For each: "name" (specific place name), "area" (town/region), and "why" (one short sentence).`;
  const text = await generate(prompt, {
    system: "You are a concise, accurate India-aware road-trip guide. Only suggest real places.",
    json: true,
    schema: PLACES_SCHEMA,
  });
  return safeParsePlaces(text);
}

/** Natural-language place search, optionally anchored near a location. */
async function searchPlaces({ query, near }) {
  const anchor = near ? ` near ${near}` : "";
  const prompt =
    `Find real places matching this request${anchor}: "${query}". ` +
    `Return up to 8 specific, real places. For each: "name", "area" (town/region), "why" (one short sentence).`;
  const text = await generate(prompt, {
    system: "You are a concise, accurate travel search assistant. Only return real, specific places.",
    json: true,
    schema: PLACES_SCHEMA,
  });
  return safeParsePlaces(text);
}

/** Free-form trip assistant / itinerary writer. Returns plain text (markdown-ish). */
async function ask({ question, context }) {
  const ctx = context
    ? `\n\nTrip context:\n${Object.entries(context)
        .filter(([, v]) => v != null && v !== "")
        .map(([k, v]) => `- ${k}: ${v}`)
        .join("\n")}`
    : "";
  const text = await generate(`${question}${ctx}`, {
    system:
      "You are Voyplan's road-trip assistant. Be concise, practical and specific. " +
      "Use short paragraphs or bullet points. When asked for an itinerary, give a clear " +
      "day-by-day plan with drive legs, stops, and meal/rest suggestions.",
  });
  return text;
}

module.exports = { recommendStops, searchPlaces, ask, AiConfigError, GEMINI_MODEL };
