const request = require("supertest");
const app = require("../index");

describe("Health & Readiness Endpoints", () => {
  test("GET /health returns 200 with status ok and version", async () => {
    const res = await request(app).get("/health");
    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty("status", "ok");
    expect(res.body).toHaveProperty("version");
    expect(res.body).toHaveProperty("timestamp");
    expect(typeof res.body.version).toBe("string");
  });

  test("GET /ready returns readiness status and checks object without leaking secrets", async () => {
    const res = await request(app).get("/ready");
    expect([200, 503]).toContain(res.status);
    expect(res.body).toHaveProperty("status");
    expect(res.body).toHaveProperty("checks");
    expect(res.body.checks).toHaveProperty("database");
    expect(res.body.checks).toHaveProperty("config");

    // Ensure no secrets are leaked in response
    const jsonStr = JSON.stringify(res.body);
    expect(jsonStr).not.toContain("sb_publishable");
    expect(jsonStr).not.toContain("password");
    expect(jsonStr).not.toContain("key");
  });
});
