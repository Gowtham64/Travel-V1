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
});
