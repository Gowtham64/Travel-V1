/**
 * Smart Fuel Range & Automatic Refuelling Stop Service for VoyPlan.
 *
 * Implements intelligent, safety-buffered multi-stop refuelling planning for
 * both ONE-WAY and AROUND (circuit/multi-stop) trips across all platforms.
 */

const { annotateCumulativeDistance, nearestRouteDistanceKm } = require('../utils/geo');
const { resolveLocation } = require('./fuelService');

class FuelRangeService {
  /**
   * Theoretical driving range (km) without safety buffer.
   */
  static calculateTheoreticalRange(fuelLiters, efficiencyKmPerLiter) {
    if (fuelLiters == null || fuelLiters < 0 || efficiencyKmPerLiter == null || efficiencyKmPerLiter <= 0) {
      return 0;
    }
    return Math.round(fuelLiters * efficiencyKmPerLiter * 100) / 100;
  }

  /**
   * Safe driving range (km) enforcing a configurable safety reserve.
   *
   * Safety reserve policy:
   *   - Reserves either a minimum fixed km (e.g. 30 km) or percentage (e.g. 10%-15%),
   *     ensuring the driver never reaches 0 fuel or risks running dry.
   */
  static calculateSafeRange(theoreticalRangeKm, options = {}) {
    if (theoreticalRangeKm <= 0) return 0;
    const {
      safetyReserveKm = 30,
      safetyReserveRatio = 0.12, // 12% reserve default
      minSafeFloorKm = 15,
    } = options;

    const reserveByRatio = theoreticalRangeKm * safetyReserveRatio;
    const appliedReserve = Math.max(safetyReserveKm, reserveByRatio);
    const safeRange = theoreticalRangeKm - appliedReserve;

    return Math.max(minSafeFloorKm, Math.round(safeRange * 10) / 10);
  }

  /**
   * Estimated remaining fuel in tank after travelling a given distance.
   */
  static calculateRemainingFuel({ startingFuelLiters = 0, distanceTravelledKm = 0, efficiencyKmPerLiter = 15.0 }) {
    if (efficiencyKmPerLiter <= 0) return Math.max(0, startingFuelLiters);
    const fuelConsumed = distanceTravelledKm / efficiencyKmPerLiter;
    const remaining = Math.max(0, startingFuelLiters - fuelConsumed);
    return Math.round(remaining * 10) / 10;
  }

  /**
   * Checks whether a destination or leg distance is reachable safely.
   */
  static isDestinationReachable(safeRangeKm, distanceToDestinationKm) {
    return safeRangeKm >= distanceToDestinationKm;
  }

  /**
   * Main Smart Refuelling Stop Planner.
   *
   * @param {Object} params
   * @param {Array<{lat:number, lng:number}>} params.routeCoordinates - Full ordered route geometry
   * @param {Array<{lat:number, lng:number, name?:string}>} [params.userStops] - User-selected stops
   * @param {Array<{id?:number|string, name?:string, lat:number, lng:number, brand?:string}>} [params.stations] - Available fuel stations along route
   * @param {Object} params.vehicle - Vehicle parameters
   * @param {number} params.vehicle.currentFuelLiters - Current fuel in tank
   * @param {number} params.vehicle.tankCapacityLiters - Vehicle tank capacity
   * @param {number} params.vehicle.efficiencyKmPerLiter - Usable mileage (user override > DB > fallback)
   * @param {string} [params.vehicle.fuelType='petrol'] - 'petrol' | 'diesel' | 'cng' | 'ev' | 'hybrid'
   * @param {Object} [params.options] - Planning options
   *
   * @returns {{
   *   needsRefuel: boolean,
   *   totalDistanceKm: number,
   *   safeRangeKm: number,
   *   unreachable: boolean,
   *   unreachableReason?: string,
   *   refuelStops: Array<{
   *     lat: number,
   *     lng: number,
   *     name: string,
   *     distanceFromStartKm: number,
   *     fuelOnArrivalLiters: number,
   *     refillLiters: number,
   *     estimatedCost: number,
   *     pricePerUnit: number,
   *     currency: string,
   *     currencySymbol: string,
   *     fuelType: string,
   *     remainingRangeAfterRefuelKm: number,
   *     offRouteKm: number,
   *     isSystemGenerated: boolean,
   *     legIndex: number
   *   }>,
   *   totalRefuelCost: number,
   *   totalRefillLiters: number
   * }}
   */
  static planSmartRefuelStops({
    routeCoordinates = [],
    userStops = [],
    stations = [],
    vehicle = {},
    options = {},
  }) {
    if (!Array.isArray(routeCoordinates) || routeCoordinates.length < 2) {
      throw new Error('routeCoordinates must contain at least 2 points');
    }

    const {
      currentFuelLiters = 14.0,
      tankCapacityLiters = 45.0,
      efficiencyKmPerLiter = 15.0,
      fuelType = 'petrol',
    } = vehicle;

    const eff = efficiencyKmPerLiter > 0 ? efficiencyKmPerLiter : 15.0;
    const tankCap = tankCapacityLiters > 0 ? tankCapacityLiters : 45.0;
    const currFuel = Math.min(tankCap, Math.max(0, currentFuelLiters != null ? currentFuelLiters : tankCap));
    const normFuel = (fuelType || 'petrol').toLowerCase().trim();

    const annotated = annotateCumulativeDistance(routeCoordinates);
    const haversineDistKm = Math.round(annotated[annotated.length - 1].cumulativeKm * 10) / 10;
    const totalDistanceKm = (typeof options.totalRouteDistanceKm === 'number' && options.totalRouteDistanceKm > 0)
      ? Math.round(options.totalRouteDistanceKm * 10) / 10
      : haversineDistKm;

    const startTheoreticalRange = this.calculateTheoreticalRange(currFuel, eff);
    const startSafeRange = this.calculateSafeRange(startTheoreticalRange, options);
    const fullTheoreticalRange = this.calculateTheoreticalRange(tankCap, eff);
    const fullSafeRange = this.calculateSafeRange(fullTheoreticalRange, options);

    // 1. If entire route can be completed on current safe range, no stops required
    if (totalDistanceKm <= startSafeRange) {
      return {
        needsRefuel: false,
        totalDistanceKm,
        safeRangeKm: startSafeRange,
        unreachable: false,
        refuelStops: [],
        totalRefuelCost: 0,
        totalRefillLiters: 0,
      };
    }

    // 2. Project and sort candidate fuel stations along the route
    const projectedStations = (stations || [])
      .map((s) => {
        const snap = nearestRouteDistanceKm(annotated, s);
        return {
          id: s.id ?? null,
          name: s.name || s.brand || 'Fuel Station',
          lat: s.lat,
          lng: s.lng,
          distanceFromStartKm: Math.round(snap.distanceFromStartKm * 10) / 10,
          offRouteKm: Math.round(snap.offRouteKm * 100) / 100,
        };
      })
      .filter((s) => s.distanceFromStartKm >= 0.5 && s.distanceFromStartKm <= totalDistanceKm + 1.0)
      .sort((a, b) => a.distanceFromStartKm - b.distanceFromStartKm);

    // 3. Iterative Multi-Stop Safe Refuel Planning
    const refuelStops = [];
    let lastStopKm = 0;
    let currentRangeRemainingKm = startTheoreticalRange;
    let unreachable = false;
    let unreachableReason = null;
    let totalRefuelCost = 0;
    let totalRefillLiters = 0;
    let iterationGuard = 0;

    // Project user stops onto route to determine leg index
    const annotatedUserStops = (userStops || []).map((u, idx) => {
      const snap = nearestRouteDistanceKm(annotated, u);
      return { ...u, index: idx, distanceFromStartKm: snap.distanceFromStartKm };
    });

    while (lastStopKm + this.calculateSafeRange(currentRangeRemainingKm, options) < totalDistanceKm) {
      iterationGuard += 1;
      if (iterationGuard > 50) {
        break; // Safety limit against infinite loops
      }

      const safeHorizonKm = lastStopKm + this.calculateSafeRange(currentRangeRemainingKm, options);
      const theoreticalHorizonKm = lastStopKm + currentRangeRemainingKm;

      // Filter candidate stations strictly BEFORE the safe fuel limit
      const reachableCandidates = projectedStations.filter(
        (s) => s.distanceFromStartKm > lastStopKm + 1.0 && s.distanceFromStartKm <= safeHorizonKm
      );

      let chosenStation = null;

      if (reachableCandidates.length > 0) {
        // Rank reachable candidates: prioritize stations with minimal detour and closest to the safe limit
        // (greedy search to maximize driving interval without risking empty tank)
        reachableCandidates.sort((a, b) => {
          // Weight: distance from start (higher is farther down the road) vs detour penalty
          const scoreA = a.distanceFromStartKm - a.offRouteKm * 2.0;
          const scoreB = b.distanceFromStartKm - b.offRouteKm * 2.0;
          return scoreB - scoreA;
        });
        chosenStation = reachableCandidates[0];
      } else {
        // Fallback: Check if there is any station before theoretical limit but past safe reserve
        const riskyCandidates = projectedStations.filter(
          (s) => s.distanceFromStartKm > lastStopKm + 1.0 && s.distanceFromStartKm <= theoreticalHorizonKm
        );
        if (riskyCandidates.length > 0) {
          chosenStation = riskyCandidates[0];
        } else {
          // Geometric synthesized stop if no OSM station exists in dataset
          const synthKm = Math.min(totalDistanceKm - 1.0, safeHorizonKm - 5.0);
          if (synthKm > lastStopKm + 2.0) {
            const synthPoint = annotated.find((p) => p.cumulativeKm >= synthKm) || annotated[annotated.length - 1];
            chosenStation = {
              id: `synth_${Math.round(synthKm)}`,
              name: 'Reachable Fuel Station',
              lat: synthPoint.lat,
              lng: synthPoint.lng,
              distanceFromStartKm: Math.round(synthKm * 10) / 10,
              offRouteKm: 0.0,
            };
          } else {
            unreachable = true;
            unreachableReason = `No suitable fuel station found before safe limit (${Math.round(safeHorizonKm)} km). Fuel level is critically low.`;
            break;
          }
        }
      }

      // Calculate fuel consumed to reach chosen station
      const legDistanceKm = chosenStation.distanceFromStartKm - lastStopKm + (chosenStation.offRouteKm || 0);
      const fuelConsumedLiters = legDistanceKm / eff;
      const fuelOnArrivalLiters = Math.max(0, Math.round(((currentRangeRemainingKm - legDistanceKm) / eff) * 10) / 10);

      // Top up to full tank capacity
      const refillLiters = Math.round((tankCap - fuelOnArrivalLiters) * 10) / 10;

      // Sourced location pricing for station
      const locPricing = resolveLocation({
        latitude: chosenStation.lat,
        longitude: chosenStation.lng,
      });
      const pricePerUnit = locPricing.prices[normFuel] || locPricing.prices.petrol || 102.86;
      const estimatedCost = Math.round(refillLiters * pricePerUnit);

      // Determine which user stop leg this belongs to
      let legIndex = 0;
      for (let i = 0; i < annotatedUserStops.length; i += 1) {
        if (chosenStation.distanceFromStartKm >= annotatedUserStops[i].distanceFromStartKm) {
          legIndex = i + 1;
        }
      }

      const stopRecord = {
        id: chosenStation.id ? `fuel_${chosenStation.id}` : `fuel_${chosenStation.lat}_${chosenStation.lng}`,
        type: 'fuel_stop',
        name: chosenStation.name || 'Fuel Station',
        stationId: chosenStation.id,
        lat: chosenStation.lat,
        lng: chosenStation.lng,
        latitude: chosenStation.lat,
        longitude: chosenStation.lng,
        distanceFromStartKm: chosenStation.distanceFromStartKm,
        fuelOnArrivalLiters,
        refillLiters,
        estimatedFuelRequired: refillLiters,
        estimatedCost,
        pricePerUnit,
        currency: locPricing.currency || 'INR',
        currencySymbol: locPricing.currencySymbol || '₹',
        fuelType: normFuel,
        remainingRangeAfterRefuelKm: fullTheoreticalRange,
        distanceFromRoute: chosenStation.offRouteKm || 0.0,
        offRouteKm: chosenStation.offRouteKm || 0.0,
        isSystemGenerated: true,
        legIndex,
      };

      refuelStops.push(stopRecord);
      totalRefuelCost += estimatedCost;
      totalRefillLiters += refillLiters;

      lastStopKm = chosenStation.distanceFromStartKm;
      currentRangeRemainingKm = fullTheoreticalRange; // Tank is now full
    }

    return {
      needsRefuel: refuelStops.length > 0,
      totalDistanceKm,
      safeRangeKm: startSafeRange,
      unreachable,
      unreachableReason,
      refuelStops,
      totalRefuelCost: Math.round(totalRefuelCost),
      totalRefillLiters: Math.round(totalRefillLiters * 10) / 10,
    };
  }
}

module.exports = {
  FuelRangeService,
};
