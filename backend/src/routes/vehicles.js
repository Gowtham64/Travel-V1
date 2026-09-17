/**
 * Vehicle Catalog and Search Routes for VoyPlan
 */

const express = require('express');
const axios = require('axios');
const crypto = require('crypto');
const router = express.Router();
const { vehicleDataProvider } = require('../services/vehicleDataProvider');
const { vehicleSyncService } = require('../services/vehicleSyncService');

// Keep image bytes in memory so repeated vehicle selections do not trigger a
// new download from Vahan Details. The cache is intentionally bounded and
// disposable; images are never written to the database or filesystem.
const IMAGE_CACHE_TTL_MS = 24 * 60 * 60 * 1000;
const IMAGE_MISS_TTL_MS = 10 * 60 * 1000;
const MAX_IMAGE_CACHE_ENTRIES = 100;
const imageCache = new Map();
const imageRequests = new Map();

function imageCacheKey(kind, brand, model) {
  return `${kind}:${brand.toLowerCase()}:${model.toLowerCase()}`;
}

function rememberImage(key, value) {
  imageCache.delete(key);
  imageCache.set(key, { ...value, expiresAt: Date.now() + value.ttlMs });
  while (imageCache.size > MAX_IMAGE_CACHE_ENTRIES) {
    imageCache.delete(imageCache.keys().next().value);
  }
}

function sendCachedImage(res, cached, key) {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Cache-Control', 'public, max-age=86400, stale-while-revalidate=604800');
  res.set('ETag', cached.etag);
  if (res.req.headers['if-none-match'] === cached.etag) return res.status(304).end();
  return res.type(cached.contentType).send(cached.data);
}

// Vahan Details does not expose browser CORS headers for its public images.
// Proxy the selected model image on demand; bytes are never persisted.
router.get('/image', async (req, res) => {
  const brand = String(req.query.brand || '').trim();
  const model = String(req.query.model || '').trim();
  const kind = String(req.query.type || '').toLowerCase() === 'motorcycle' ? 'Bikes' : 'Cars';
  if (!brand || !model) return res.status(400).json({ error: 'brand and model are required' });
  const cacheKey = imageCacheKey(kind, brand, model);
  const cached = imageCache.get(cacheKey);
  if (cached && cached.expiresAt > Date.now()) {
    return cached.data ? sendCachedImage(res, cached, cacheKey) : res.status(404).json({ error: 'Vehicle image not found' });
  }
  imageCache.delete(cacheKey);

  const sourceBrand = brand.toLowerCase() === 'tata motors'
    ? 'Tata'
    : (brand.toLowerCase() === 'mg motor' || brand.toLowerCase() === 'mg motors' ? 'MG' : brand);
  const models = [...new Set([model, model.replace(/\.ev$/i, ' EV'), model.replace(/\./g, '')])];
  const candidates = [];
  for (const modelName of models) {
    const folders = [...new Set([`${sourceBrand} ${modelName}`, `${brand} ${modelName}`])];
    const prefixes = [...new Set([
      `${brand}-${sourceBrand} ${modelName}`,
      `${brand}-${brand} ${modelName}`,
      `${brand}-${modelName}`,
    ])];
    for (const folder of folders) {
      for (const prefix of prefixes) {
        candidates.push(`https://restapi.vahandetails.com/public/Vahandetails_Images/${kind}/${encodeURIComponent(brand)}/${encodeURIComponent(folder)}/${encodeURIComponent(`${prefix}-vahandetails-com1.webp`)}`);
      }
    }
  }

  const pending = imageRequests.get(cacheKey) || (async () => {
    for (const imageUrl of candidates) {
      try {
        const image = await axios.get(imageUrl, {
          responseType: 'arraybuffer',
          timeout: 6000,
          validateStatus: () => true,
        });
        const contentType = String(image.headers['content-type'] || '');
        if (image.status >= 200 && image.status < 300 && contentType.startsWith('image/')) {
          const data = Buffer.from(image.data);
          rememberImage(cacheKey, {
            data,
            contentType,
            etag: `"${crypto.createHash('sha1').update(data).digest('hex')}"`,
            ttlMs: IMAGE_CACHE_TTL_MS,
          });
          return imageCache.get(cacheKey);
        }
      } catch (_) {
        // Try the next naming variant.
      }
    }
    rememberImage(cacheKey, { data: null, ttlMs: IMAGE_MISS_TTL_MS });
    return imageCache.get(cacheKey);
  })();
  imageRequests.set(cacheKey, pending);
  try {
    const image = await pending;
    return image.data ? sendCachedImage(res, image, cacheKey) : res.status(404).json({ error: 'Vehicle image not found' });
  } finally {
    if (imageRequests.get(cacheKey) === pending) imageRequests.delete(cacheKey);
  }
});

// 1. List all vehicle brands
router.get('/brands', async (req, res) => {
  try {
    const brands = await vehicleDataProvider.getBrands();
    res.json({ success: true, brands });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// 2. List models for a brand
router.get('/models', async (req, res) => {
  try {
    const { brandId } = req.query;
    if (!brandId) {
      return res.status(400).json({ error: 'Missing brandId query parameter' });
    }
    const models = await vehicleDataProvider.getModels(brandId);
    res.json({ success: true, brandId, models });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// 3. List variants for a model
router.get('/variants', async (req, res) => {
  try {
    const { modelId } = req.query;
    if (!modelId) {
      return res.status(400).json({ error: 'Missing modelId query parameter' });
    }
    const variants = await vehicleDataProvider.getVariants(modelId);
    res.json({ success: true, modelId, variants });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// 4. Get complete vehicle details by ID
router.get('/details', async (req, res) => {
  try {
    const { id } = req.query;
    if (!id) {
      return res.status(400).json({ error: 'Missing vehicle id query parameter' });
    }
    const details = await vehicleDataProvider.getVehicleDetails(id);
    if (!details) {
      return res.status(404).json({ error: 'Vehicle not found' });
    }
    res.json({ success: true, vehicle: details });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// 5. Search vehicles by query text, fuelType, and type (car/motorcycle)
router.get('/search', async (req, res) => {
  try {
    const { q, fuelType, type, limit } = req.query;
    const results = await vehicleDataProvider.searchVehicles(q || '', {
      fuelType,
      type,
      limit: limit ? parseInt(limit, 10) : 25,
    });
    res.json({
      success: true,
      query: q || '',
      count: results.length,
      vehicles: results,
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// 6. Admin / Monitoring status
router.get('/status', async (req, res) => {
  try {
    const status = await vehicleSyncService.getMonitoringStatus();
    res.json({ success: true, monitoring: status });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// 7. Trigger manual vehicle sync
router.post('/sync', async (req, res) => {
  try {
    const result = await vehicleSyncService.runSync();
    res.json({ success: true, result });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
