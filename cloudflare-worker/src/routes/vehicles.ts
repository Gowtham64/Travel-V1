import { Hono } from 'hono';
import type { Env, AppVariables } from '../types/env';
import { vehicleDataProvider } from '../services/vehicleDataProvider';
import { vehicleSyncService } from '../services/vehicleSyncService';

const vehicles = new Hono<{ Bindings: Env; Variables: AppVariables }>();

const IMAGE_CACHE_TTL_MS = 24 * 60 * 60 * 1000;
const IMAGE_MISS_TTL_MS = 10 * 60 * 1000;
const MAX_IMAGE_CACHE_ENTRIES = 150;
const imageCache = new Map<string, { url: string | null; expiresAt: number }>();
const imageRequests = new Map<string, Promise<{ url: string | null; expiresAt: number }>>();

function imageCacheKey(kind: string, brand: string, model: string) {
  return `${kind}:${brand.toLowerCase()}:${model.toLowerCase()}`;
}

function rememberImage(key: string, url: string | null, ttlMs: number) {
  imageCache.delete(key);
  imageCache.set(key, { url, expiresAt: Date.now() + ttlMs });
  while (imageCache.size > MAX_IMAGE_CACHE_ENTRIES) {
    const firstKey = imageCache.keys().next().value;
    if (firstKey) imageCache.delete(firstKey);
  }
}

// Vehicle model image resolver via 302 redirect directly to external CDN
vehicles.get('/image', async (c) => {
  const brand = String(c.req.query('brand') || '').trim();
  const model = String(c.req.query('model') || '').trim();
  const kind = String(c.req.query('type') || '').toLowerCase() === 'motorcycle' ? 'Bikes' : 'Cars';

  if (!brand || !model) {
    return c.json({ error: 'brand and model are required' }, 400);
  }

  const cacheKey = imageCacheKey(kind, brand, model);
  const cached = imageCache.get(cacheKey);

  if (cached && cached.expiresAt > Date.now()) {
    if (cached.url) {
      c.header('Access-Control-Allow-Origin', '*');
      c.header('Cache-Control', 'public, max-age=86400, stale-while-revalidate=604800');
      return c.redirect(cached.url, 302);
    }
    return c.json({ error: 'Vehicle image not found' }, 404);
  }
  imageCache.delete(cacheKey);

  const sourceBrand =
    brand.toLowerCase() === 'tata motors'
      ? 'Tata'
      : brand.toLowerCase() === 'mg motor' || brand.toLowerCase() === 'mg motors'
      ? 'MG'
      : brand;

  const models = [...new Set([model, model.replace(/\.ev$/i, ' EV'), model.replace(/\./g, '')])];
  const candidates: string[] = [];

  for (const modelName of models) {
    const folders = [...new Set([`${sourceBrand} ${modelName}`, `${brand} ${modelName}`])];
    const prefixes = [...new Set([
      `${brand}-${sourceBrand} ${modelName}`,
      `${brand}-${brand} ${modelName}`,
      `${brand}-${modelName}`,
    ])];
    for (const folder of folders) {
      for (const prefix of prefixes) {
        candidates.push(
          `https://restapi.vahandetails.com/public/Vahandetails_Images/${kind}/${encodeURIComponent(brand)}/${encodeURIComponent(folder)}/${encodeURIComponent(`${prefix}-vahandetails-com1.webp`)}`
        );
      }
    }
  }

  const pending =
    imageRequests.get(cacheKey) ||
    (async () => {
      for (const imageUrl of candidates) {
        try {
          const res = await fetch(imageUrl, {
            method: 'HEAD',
            signal: AbortSignal.timeout(3500),
          });
          if (res.status >= 200 && res.status < 300) {
            rememberImage(cacheKey, imageUrl, IMAGE_CACHE_TTL_MS);
            return imageCache.get(cacheKey)!;
          }
        } catch (_) {
          // Probe next candidate
        }
      }
      rememberImage(cacheKey, null, IMAGE_MISS_TTL_MS);
      return imageCache.get(cacheKey)!;
    })();

  imageRequests.set(cacheKey, pending);

  try {
    const image = await pending;
    if (image && image.url) {
      c.header('Access-Control-Allow-Origin', '*');
      c.header('Cache-Control', 'public, max-age=86400, stale-while-revalidate=604800');
      return c.redirect(image.url, 302);
    }
    return c.json({ error: 'Vehicle image not found' }, 404);
  } finally {
    if (imageRequests.get(cacheKey) === pending) imageRequests.delete(cacheKey);
  }
});

// 1. List all vehicle brands
vehicles.get('/brands', async (c) => {
  c.header('Cache-Control', 'public, max-age=3600, stale-while-revalidate=86400');
  try {
    const brands = await vehicleDataProvider.getBrands();
    return c.json({ success: true, brands });
  } catch (err: any) {
    return c.json({ error: err?.message || 'Failed to fetch brands' }, 500);
  }
});

// 2. List models for a brand
vehicles.get('/models', async (c) => {
  c.header('Cache-Control', 'public, max-age=3600, stale-while-revalidate=86400');
  try {
    const brandId = c.req.query('brandId') || c.req.query('brand');
    if (!brandId) return c.json({ error: 'Missing brandId query parameter' }, 400);
    const models = await vehicleDataProvider.getModels(brandId);
    return c.json({ success: true, brandId, models });
  } catch (err: any) {
    return c.json({ error: err?.message || 'Failed to fetch models' }, 500);
  }
});

// 3. List variants for a model
vehicles.get('/variants', async (c) => {
  c.header('Cache-Control', 'public, max-age=3600, stale-while-revalidate=86400');
  try {
    const modelId = c.req.query('modelId');
    if (!modelId) return c.json({ error: 'Missing modelId query parameter' }, 400);
    const variants = await vehicleDataProvider.getVariants(modelId);
    return c.json({ success: true, modelId, variants });
  } catch (err: any) {
    return c.json({ error: err?.message || 'Failed to fetch variants' }, 500);
  }
});

// 4. Get complete vehicle details by ID
vehicles.get('/details', async (c) => {
  c.header('Cache-Control', 'public, max-age=3600, stale-while-revalidate=86400');
  try {
    const id = c.req.query('id');
    if (!id) return c.json({ error: 'Missing vehicle id query parameter' }, 400);
    const details = await vehicleDataProvider.getVehicleDetails(id);
    if (!details) return c.json({ error: 'Vehicle not found' }, 404);
    return c.json({ success: true, vehicle: details });
  } catch (err: any) {
    return c.json({ error: err?.message || 'Failed to fetch vehicle details' }, 500);
  }
});

// 5. Search vehicles by query text, fuelType, and type
vehicles.get('/search', async (c) => {
  c.header('Cache-Control', 'public, max-age=300, stale-while-revalidate=1800');
  try {
    const q = c.req.query('q') || '';
    const fuelType = c.req.query('fuelType');
    const type = c.req.query('type');
    const limit = c.req.query('limit');

    const results = await vehicleDataProvider.searchVehicles(q, {
      fuelType,
      type,
      limit: limit ? parseInt(limit, 10) : 25,
    });

    return c.json({
      success: true,
      query: q,
      count: results.length,
      vehicles: results,
    });
  } catch (err: any) {
    return c.json({ error: err?.message || 'Search failed' }, 500);
  }
});

// 6. Admin / Monitoring status
vehicles.get('/status', async (c) => {
  try {
    const status = await vehicleSyncService.getMonitoringStatus();
    return c.json({ success: true, monitoring: status });
  } catch (err: any) {
    return c.json({ error: err?.message || 'Failed to get status' }, 500);
  }
});

// 7. Trigger manual vehicle sync
vehicles.post('/sync', async (c) => {
  try {
    const result = await vehicleSyncService.runSync();
    return c.json({ success: true, result });
  } catch (err: any) {
    return c.json({ error: err?.message || 'Sync failed' }, 500);
  }
});

export default vehicles;
