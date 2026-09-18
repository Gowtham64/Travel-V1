import { afterEach, describe, it, expect, vi } from "vitest";
import app from "../src/index";

const mockEnv = {
  SUPABASE_URL: "https://mock-project.supabase.co",
  SUPABASE_ANON_KEY: "mock-anon-key",
  SUPABASE_SERVICE_ROLE_KEY: "mock-service-role-key",
  GEMINI_API_KEY: "mock-gemini-key",
  MAPBOX_TOKEN: "mock-mapbox-token",
  OPENROUTE_SERVICE_API_KEY: "mock-ors-key",
  NODE_ENV: "test",
};

describe("VoyPlan Cloudflare Worker API", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  describe("Health & Liveness", () => {
    it("GET /health returns 200 with service metadata", async () => {
      const res = await app.request("/health", {}, mockEnv);
      expect(res.status).toBe(200);
      const json = await res.json() as any;
      expect(json.status).toBe("ok");
      expect(json.service).toBe("voyplan-api");
      expect(json.version).toBeDefined();
    });

    it("GET /ready returns 200 ready state", async () => {
      const res = await app.request("/ready", {}, mockEnv);
      expect(res.status).toBe(200);
      const json = await res.json() as any;
      expect(json.status).toBe("ready");
    });

    it("GET /status returns HTML APM dashboard", async () => {
      const res = await app.request("/status", {}, mockEnv);
      expect(res.status).toBe(200);
      const text = await res.text();
      expect(text).toContain("Voyplan APM");
      expect(text).toContain("Cloudflare Workers");
    });

    it("GET /api/metrics returns live APM metrics", async () => {
      const res = await app.request("/api/metrics", {}, mockEnv);
      expect(res.status).toBe(200);
      const json = await res.json() as any;
      expect(json.service).toBe("voyplan-api");
      expect(json.runtime).toContain("Cloudflare Workers");
      expect(json.system).toBeDefined();
      expect(json.dependencies).toBeDefined();
    });
  });

  describe("CORS & Preflight", () => {
    it("OPTIONS preflight returns 204 with allowed origin echoing", async () => {
      const res = await app.request(
        "/api/trip/calculate-route",
        {
          method: "OPTIONS",
          headers: {
            Origin: "https://voyplan.in",
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "Content-Type, Authorization",
          },
        },
        mockEnv
      );
      expect(res.status).toBe(204);
      expect(res.headers.get("Access-Control-Allow-Origin")).toBe("https://voyplan.in");
      expect(res.headers.get("Access-Control-Allow-Methods")).toContain("POST");
    });

    it("OPTIONS preflight with any web origin is allowed", async () => {
      const res = await app.request(
        "/api/trip/calculate-route",
        {
          method: "OPTIONS",
          headers: {
            Origin: "http://localhost:3000",
            "Access-Control-Request-Method": "POST",
          },
        },
        mockEnv
      );
      expect(res.status).toBe(204);
      expect(res.headers.get("Access-Control-Allow-Origin")).toBe("http://localhost:3000");
    });
  });

  describe("Vehicle Registry Routes", () => {
    it("GET /api/vehicles/brands returns brands list", async () => {
      const res = await app.request("/api/vehicles/brands", {}, mockEnv);
      expect(res.status).toBe(200);
      const json = await res.json() as any;
      expect(json.success).toBe(true);
      expect(Array.isArray(json.brands)).toBe(true);
      expect(json.brands.length).toBeGreaterThan(0);
      expect(json.brands.some((b: any) => b.id === "tata" || b.name === "Tata")).toBe(true);
    });

    it("GET /api/vehicles/models returns models for a valid brandId", async () => {
      const res = await app.request("/api/vehicles/models?brandId=tata", {}, mockEnv);
      expect(res.status).toBe(200);
      const json = await res.json() as any;
      expect(json.success).toBe(true);
      expect(json.brandId).toBe("tata");
      expect(Array.isArray(json.models)).toBe(true);
      expect(json.models.length).toBeGreaterThan(0);
    });

    it("GET /api/vehicles/search returns search results", async () => {
      const res = await app.request("/api/vehicles/search?q=nexon", {}, mockEnv);
      expect(res.status).toBe(200);
      const json = await res.json() as any;
      expect(json.success).toBe(true);
      expect(Array.isArray(json.vehicles)).toBe(true);
    });
  });

  describe("Fuel Routes", () => {
    it("GET /api/fuel/prices returns prices for a location", async () => {
      const res = await app.request("/api/fuel/prices?locationName=Bengaluru", {}, mockEnv);
      expect(res.status).toBe(200);
      const json = await res.json() as any;
      expect(json.country).toBe("India");
      expect(json.state).toBe("Karnataka");
      expect(json.price).toBeGreaterThan(0);
      expect(json.allPrices).toBeDefined();
      expect(json.allPrices.petrol).toBeGreaterThan(0);
    });
  });

  describe("Authentication & Protection", () => {
    it("GET /api/account/profile returns 401 when Authorization header is missing", async () => {
      const res = await app.request("/api/account/profile", {}, mockEnv);
      expect(res.status).toBe(401);
      const json = await res.json() as any;
      expect(json.error).toContain("Authorization");
    });

    it("GET /api/account/profile returns 401 when Bearer token is invalid", async () => {
      const res = await app.request(
        "/api/account/profile",
        {
          headers: {
            Authorization: "Bearer invalid-token-xyz",
          },
        },
        mockEnv
      );
      expect(res.status).toBe(401);
      const json = await res.json() as any;
      expect(json.error).toBeDefined();
    });
  });

  describe("Security Headers & Rate Limiting", () => {
    it("responses include security headers and X-Request-ID", async () => {
      const res = await app.request("/health", {}, mockEnv);
      expect(res.headers.get("X-Content-Type-Options")).toBe("nosniff");
      expect(res.headers.get("X-Frame-Options")).toBe("SAMEORIGIN");
      expect(res.headers.get("X-Request-ID")).toBeDefined();
    });

    it("responses include rate limit headers", async () => {
      const res = await app.request("/health", {}, mockEnv);
      expect(res.headers.get("X-RateLimit-Limit")).toBeDefined();
      expect(res.headers.get("X-RateLimit-Remaining")).toBeDefined();
    });
  });

  describe("Treks & Currency", () => {
    it("GET /api/treks returns 400 when lat/lng missing", async () => {
      const res = await app.request("/api/treks", {}, mockEnv);
      expect(res.status).toBe(400);
      const json = await res.json() as any;
      expect(json.error).toContain("lat and lng");
    });

    it("GET /api/treks/geometry returns 400 when id missing", async () => {
      const res = await app.request("/api/treks/geometry", {}, mockEnv);
      expect(res.status).toBe(400);
      const json = await res.json() as any;
      expect(json.error).toContain("id query param is required");
    });

    it("GET /api/currency/rates returns exchange rates", async () => {
      vi.stubGlobal(
        "fetch",
        vi.fn().mockResolvedValue(
          new Response(
            JSON.stringify({ result: "success", rates: { INR: 83.2 } }),
            { status: 200, headers: { "Content-Type": "application/json" } }
          )
        )
      );

      const res = await app.request("/api/currency/rates", {}, mockEnv);
      expect(res.status).toBe(200);
      const json = await res.json() as any;
      expect(json.base).toBe("USD");
      expect(json.rates).toBeDefined();
      expect(json.rates.INR).toBeDefined();
    });
  });

  describe("AI Routes", () => {
    it("GET /api/ai/status returns AI engine status", async () => {
      const res = await app.request("/api/ai/status", {}, mockEnv);
      expect(res.status).toBe(200);
      const json = await res.json() as any;
      expect(json.provider).toBeDefined();
      expect(typeof json.configured).toBe("boolean");
    });

    it("POST /api/ai/recommend returns 400 when location missing", async () => {
      const res = await app.request(
        "/api/ai/recommend",
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({}),
        },
        mockEnv
      );
      expect(res.status).toBe(400);
      const json = await res.json() as any;
      expect(json.error).toBeDefined();
    });
  });

  describe("Validation & Error Handling", () => {
    it("POST /api/trip/calculate-route returns 400 if start or end location missing", async () => {
      const res = await app.request(
        "/api/trip/calculate-route",
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({}),
        },
        mockEnv
      );
      expect(res.status).toBe(400);
      const json = await res.json() as any;
      expect(json.error).toBeDefined();
      expect(json.error).toContain("coordinates");
    });

    it("GET /nonexistent-route returns 404 with requestId", async () => {
      const res = await app.request("/nonexistent-route", {}, mockEnv);
      expect(res.status).toBe(404);
      const json = await res.json() as any;
      expect(json.error).toBe("Not found");
      expect(json.requestId).toBeDefined();
    });
  });
});
