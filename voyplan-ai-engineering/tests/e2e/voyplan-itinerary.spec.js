// @ts-check
const { test, expect } = require("@playwright/test");

function targetUrl(baseURL) {
  expect(baseURL, "Set STAGING_URL or PRODUCTION_URL before running real-product E2E").toBeTruthy();
  return baseURL.replace(/\/$/, "");
}

test.describe("VoyPlan Web Application & Itinerary Planner E2E Suite", () => {
  test("Landing page loads and displays core CTA", async ({ page, baseURL }) => {
    await page.goto(targetUrl(baseURL));
    await expect(page).toHaveTitle(/Voyplan/i);
    const bodyText = await page.textContent("body");
    expect(bodyText).toContain("Voyplan");
  });

  test("App client route loads without fatal errors", async ({ page, baseURL }) => {
    const appUrl = targetUrl(baseURL) + "/app/";
    const response = await page.goto(appUrl);
    expect(response?.status()).toBeLessThan(400);
  });

  test("Backend API health and model status", async ({ request, baseURL }) => {
    const res = await request.get(`${targetUrl(baseURL)}/api/status`);
    expect(res.ok(), `status API returned ${res.status()}`).toBeTruthy();
    expect(await res.json()).toBeDefined();
  });

  test("Destination integrity E2E regression validation", async ({ request, baseURL }) => {
    const response = await request.post(`${targetUrl(baseURL)}/api/ai/smart-itinerary`, {
      data: {
        startLocation: "Bengaluru", destination: "Tirumala", durationDays: 1,
        selectedCategories: ["Temples"],
      }, timeout: 45000,
    });
    expect(response.ok(), `smart-itinerary returned ${response.status()}`).toBeTruthy();
    const body = await response.json();
    const days = body.days || [];
    expect(days.length, "A successful itinerary must include at least one day").toBeGreaterThan(0);
    for (const day of days) {
      for (const block of day.blocks || []) {
        const place = `${block.title} ${block.place || ""}`.toLowerCase();
        expect(place).not.toContain("bengaluru");
        expect(place).not.toContain("mysuru");
        expect(place).not.toContain("chennai");
        expect(place).not.toContain("hyderabad");
      }
    }
  });
});
