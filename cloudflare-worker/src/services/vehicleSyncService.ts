import { vehicleDataProvider } from './vehicleDataProvider';
import { fuelPriceProvider } from './fuelPriceProvider';

export class VehicleSyncService {
  private _syncLogs: Array<any> = [];
  private _stats = {
    totalVehicles: 0,
    activeVehicles: 0,
    updatedVehicles: 0,
    newVehicles: 0,
    discontinuedVehicles: 0,
    lastSyncTime: null as string | null,
    lastSyncStatus: 'INITIALIZED',
    dataVersion: '2026.3.1',
    totalBrands: 0,
  };

  validateVehicle(vehicle: any) {
    const errors: string[] = [];
    if (!vehicle.brandId || !vehicle.brandName) errors.push('Missing brand');
    if (!vehicle.modelId || !vehicle.modelName) errors.push('Missing model');
    if (!vehicle.variantId || !vehicle.variantName) errors.push('Missing variant');
    if (!vehicle.fuelType) errors.push('Missing fuel type');

    const validFuelTypes = ['petrol', 'diesel', 'cng', 'ev', 'hybrid'];
    const normFuel = (vehicle.fuelType || '').toLowerCase().trim();
    if (!validFuelTypes.includes(normFuel)) {
      errors.push(`Invalid fuel type: ${vehicle.fuelType}`);
    }

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
    } catch (err: any) {
      this._stats.lastSyncStatus = 'FAILED';
      this._syncLogs.unshift({
        timestamp: new Date().toISOString(),
        status: 'FAILED',
        error: err?.message || String(err),
      });
      throw err;
    }
  }

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

export const vehicleSyncService = new VehicleSyncService();
