process.env.ALLOWED_ORIGINS = 'https://voyplan.in,https://www.voyplan.in';

const request = require('supertest');
const app = require('../index');

describe('deployment delivery controls', () => {
  test('allows the production Pages origin', async () => {
    const response = await request(app)
      .get('/health')
      .set('Origin', 'https://voyplan.in');

    expect(response.status).toBe(200);
    expect(response.headers['access-control-allow-origin']).toBe('https://voyplan.in');
  });

  test('allows Cloudflare Pages preview origins (*.pages.dev)', async () => {
    const response = await request(app)
      .get('/health')
      .set('Origin', 'https://voyplan-preview-123.pages.dev');

    expect(response.status).toBe(200);
    expect(response.headers['access-control-allow-origin']).toBe('https://voyplan-preview-123.pages.dev');
  });

  test('does not allow an unconfigured browser origin', async () => {
    const response = await request(app)
      .get('/health')
      .set('Origin', 'https://untrusted.example');

    expect(response.status).toBe(200);
    expect(response.headers['access-control-allow-origin']).toBeUndefined();
  });

  test('compresses and caches the public vehicle catalog', async () => {
    const response = await request(app)
      .get('/api/vehicles/brands')
      .set('Accept-Encoding', 'gzip');

    expect(response.status).toBe(200);
    expect(response.headers['content-encoding']).toBe('gzip');
    expect(response.headers['cache-control']).toContain('public');
  });

  test('caches public fuel prices', async () => {
    const response = await request(app)
      .get('/api/fuel/prices?country=IN');

    expect(response.status).toBe(200);
    expect(response.headers['cache-control']).toContain('public');
  });

  test('caches public geocode autocomplete suggestions', async () => {
    const response = await request(app)
      .get('/api/geocode/suggest?q=Delhi');

    expect(response.status).toBe(200);
    expect(response.headers['cache-control']).toContain('public');
  });

  test('reports telemetry with response bytes tracking', async () => {
    const response = await request(app)
      .get('/api/metrics');

    expect(response.status).toBe(200);
    expect(response.body.telemetry).toBeDefined();
    expect(response.body.telemetry.totalResponseBytes).toBeDefined();
    expect(typeof response.body.telemetry.totalResponseBytes).toBe('number');
  });
});
