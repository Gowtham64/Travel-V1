import { Hono } from 'hono';
import type { Env, AppVariables } from '../types/env';
import { getFuelPrices, calculateRouteFuel } from '../services/fuelService';
import { fuelPriceProvider } from '../services/fuelPriceProvider';

const fuel = new Hono<{ Bindings: Env; Variables: AppVariables }>();

// GET /api/fuel/prices
fuel.get('/prices', (c) => {
  try {
    const location = c.req.query('location');
    const country = c.req.query('country');
    const lat = c.req.query('lat');
    const lng = c.req.query('lng');
    const fuelType = c.req.query('fuelType');

    const result = getFuelPrices({
      locationName: location || '',
      countryCode: country || 'IN',
      lat: lat ? parseFloat(lat) : undefined,
      lng: lng ? parseFloat(lng) : undefined,
      fuelType: (fuelType || 'petrol') as any,
    });

    c.header('Cache-Control', 'public, max-age=14400, stale-while-revalidate=86400');
    return c.json(result);
  } catch (err: any) {
    return c.json({ error: 'Failed to retrieve fuel prices', message: err?.message }, 500);
  }
});

// POST /api/fuel/calculate
fuel.post('/calculate', async (c) => {
  try {
    const body = (await c.req.json().catch(() => ({}))) as any;
    const {
      distanceKm = 0,
      vehicleEfficiency = 15.0,
      fuelType = 'petrol',
      startLocation = '',
      endLocation = '',
      routeCoordinates = [],
    } = body;

    const calculation = calculateRouteFuel({
      distanceKm: Number(distanceKm),
      vehicleEfficiency: Number(vehicleEfficiency),
      fuelType,
      startLocation,
      endLocation,
      routeCoordinates,
    });

    return c.json(calculation);
  } catch (err: any) {
    return c.json({ error: 'Failed to calculate route fuel', message: err?.message }, 500);
  }
});

// GET /api/fuel/provider-prices
fuel.get('/provider-prices', async (c) => {
  try {
    const country = c.req.query('country') || 'India';
    const state = c.req.query('state') || 'Karnataka';
    const city = c.req.query('city') || 'Bengaluru';
    const fuelType = c.req.query('fuelType') || 'PETROL';

    const priceData = await fuelPriceProvider.getFuelPrice(country, state, city, fuelType);
    return c.json({ success: true, fuelPrice: priceData });
  } catch (err: any) {
    return c.json({ error: 'Failed to retrieve provider fuel price', message: err?.message }, 500);
  }
});

export default fuel;
