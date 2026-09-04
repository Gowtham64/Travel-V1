const express = require('express');
const fuelService = require('../services/fuelService');

const router = express.Router();

/**
 * GET /api/fuel/prices
 * Query params:
 * - location: string (city, state, or address)
 * - country: string (IN, US, GB, AE)
 * - lat: number (optional)
 * - lng: number (optional)
 * - fuelType: string ('petrol', 'diesel', 'cng', 'ev')
 */
router.get('/prices', (req, res) => {
  try {
    const { location, country, lat, lng, fuelType } = req.query;
    const parsedLat = lat ? parseFloat(lat) : undefined;
    const parsedLng = lng ? parseFloat(lng) : undefined;

    const result = fuelService.getFuelPrices({
      locationName: location || '',
      countryCode: country || 'IN',
      lat: parsedLat,
      lng: parsedLng,
      fuelType: fuelType || 'petrol'
    });

    res.json(result);
  } catch (err) {
    res.status(500).json({ error: 'Failed to retrieve fuel prices', message: err.message });
  }
});

/**
 * POST /api/fuel/calculate
 * Body:
 * {
 *   distanceKm: number,
 *   vehicleEfficiency: number,
 *   fuelType: 'petrol' | 'diesel' | 'cng' | 'ev',
 *   startLocation: string,
 *   endLocation: string,
 *   routeCoordinates?: Array<{lat: number, lng: number}>
 * }
 */
router.post('/calculate', (req, res) => {
  try {
    const {
      distanceKm = 0,
      vehicleEfficiency = 15.0,
      fuelType = 'petrol',
      startLocation = '',
      endLocation = '',
      routeCoordinates = []
    } = req.body;

    const calculation = fuelService.calculateRouteFuel({
      distanceKm: Number(distanceKm),
      vehicleEfficiency: Number(vehicleEfficiency),
      fuelType,
      startLocation,
      endLocation,
      routeCoordinates
    });

    res.json(calculation);
  } catch (err) {
    res.status(500).json({ error: 'Failed to calculate route fuel', message: err.message });
  }
});

/**
 * GET /api/fuel/provider-prices
 * Query CarDekho / Authorized provider structure
 */
const { fuelPriceProvider } = require('../services/fuelPriceProvider');

router.get('/provider-prices', async (req, res) => {
  try {
    const { country = 'India', state = 'Karnataka', city = 'Bengaluru', fuelType = 'PETROL' } = req.query;
    const priceData = await fuelPriceProvider.getFuelPrice(country, state, city, fuelType);
    res.json({ success: true, fuelPrice: priceData });
  } catch (err) {
    res.status(500).json({ error: 'Failed to retrieve provider fuel price', message: err.message });
  }
});

module.exports = router;
