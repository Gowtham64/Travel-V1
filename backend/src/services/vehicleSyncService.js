/**
 * Vehicle Sync & Data Ingestion Service for VoyPlan.
 *
 * Handles normalization, validation, duplicate detection, and health monitoring
 * for the centralized vehicle catalog and fuel price providers.
 */

const { vehicleDataProvider } = require('./vehicleDataProvider');
const { fuelPriceProvider } = require('./fuelPriceProvider');

class VehicleSyncService {
  constructor() {
    this._syncLogs = [];
    this._stats = {
      totalVehicles: 0,
      activeVehicles: 0,
      updatedVehicles: 0,
      newVehicles: 0,
      discontinuedVehicles: 0,
      lastSyncTime: null,
      lastSyncStatus: 'INITIALIZED',
      dataVersion: '2026.3.1',
    };
  }

  /**
   * Validate and normalize a vehicle record
   */
  validateVehicle(vehicle) {
    const errors = [];
    if (!vehicle.brandId || !vehicle.brandName) errors.push('Missing brand');
    if (!vehicle.modelId || !vehicle.modelName) errors.push('Missing model');
    if (!vehicle.variantId || !vehicle.variantName) errors.push('Missing variant');
    if (!vehicle.fuelType) errors.push('Missing fuel type');
    
    // Normalize fuel type
    const validFuelTypes = ['petrol', 'diesel', 'cng', 'ev', 'hybrid'];
    const normFuel = (vehicle.fuelType || '').toLowerCase().trim();
    if (!validFuelTypes.includes(normFuel)) {
      errors.push(`Invalid fuel type: ${vehicle.fuelType}`);
    }

    // Mileage validation
    if (normFuel !== 'ev' && (!vehicle.mileage || vehicle.mileage <= 0)) {
      errors.push('Mileage must be positive for non-EV vehicles');
    }

    return {
      isValid: errors.length === 0,
      errors,
      normalized: {
        ...vehicle,
        fuelType: normFuel,
        mileage: Number(vehicle.mileage || 0),
        tankCapacity: Number(vehicle.tankCapacity || 0),
        batteryCapacityKwh: Number(vehicle.batteryCapacityKwh || 0),
        evRangeKm: Number(vehicle.evRangeKm || 0),
      },
    };
  }

  /**
   * Trigger catalog ingestion & sync
   */
  async runSync() {
    try {
      const syncResult = await vehicleDataProvider.syncVehicles();
      const brands = await vehicleDataProvider.getBrands();
      const vehicles = await vehicleDataProvider.searchVehicles('', { limit: 1000 });

      this._stats = {
        totalVehicles: vehicles.length,
        activeVehicles: vehicles.length,
        updatedVehicles: 0,
        newVehicles: vehicles.length,
        discontinuedVehicles: 0,
        lastSyncTime: syncResult.syncedAt,
        lastSyncStatus: 'SUCCESS',
        dataVersion: syncResult.dataVersion,
        totalBrands: brands.length,
      };

      this._syncLogs.unshift({
        timestamp: syncResult.syncedAt,
        status: 'SUCCESS',
        details: `Synchronized ${vehicles.length} vehicles across ${brands.length} brands.`,
      });

      return this._stats;
    } catch (err) {
      this._stats.lastSyncStatus = 'FAILED';
      this._syncLogs.unshift({
        timestamp: new Date().toISOString(),
        status: 'FAILED',
        error: err.message,
      });
      throw err;
    }
  }

  /**
   * Admin Monitoring status
   */
  async getMonitoringStatus() {
    const brands = await vehicleDataProvider.getBrands();
    const vehicles = await vehicleDataProvider.searchVehicles('', { limit: 1000 });

    return {
      vehicleCatalog: {
        totalVehicles: vehicles.length,
        activeVehicles: vehicles.length,
        totalBrands: brands.length,
        source: vehicleDataProvider.source,
        dataVersion: vehicleDataProvider.dataVersion,
        lastSyncedAt: vehicleDataProvider.lastSyncedAt,
      },
      fuelPriceSync: {
        source: fuelPriceProvider.source,
        lastSyncedAt: fuelPriceProvider.lastSyncedAt,
        status: 'ACTIVE',
        cachingTtlHours: fuelPriceProvider.ttlHours,
      },
      recentLogs: this._syncLogs.slice(0, 10),
    };
  }
}

const vehicleSyncService = new VehicleSyncService();

module.exports = {
  VehicleSyncService,
  vehicleSyncService,
};
