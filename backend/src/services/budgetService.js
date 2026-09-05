/**
 * Estimate a full trip budget: fuel + tolls + transport tickets (flight/train/
 * bus/ferry) + local transport at the destination + food + stay + a buffer.
 *
 * The routing/fuel/toll services give the hard driving numbers; this layer adds
 * the "human" costs so the user sees a single all-in figure. For trips outside
 * India it switches to international food/stay rates and prices destination
 * getting-around as taxis rather than personal-car fuel.
 *
 * Figures are in INR. Per-person/per-day rates are rough mid-range defaults and
 * can be overridden by the caller.
 */

const fuelService = require("./fuelService");

const DEFAULTS = {
  fuelPricePerLiter: 102.86, // Dynamic fallback, will be resolved by location
  foodPerDay: 600, // per person, 3 meals mid-range (India)
  stayPerNight: 1800, // mid-range hotel room (India)
  travellers: 1,
  bufferRatio: 0.1, // 10% miscellaneous buffer (parking, snacks, etc.)
  localTaxiPerKm: 18, // destination taxis/ride-hail, per km for the group
};

// International food/stay are markedly higher than India mid-range.
const INTL_DEFAULTS = {
  foodPerDay: 2500, // per person, 3 meals mid-range abroad
  stayPerNight: 7000, // mid-range hotel room abroad
  localTaxiPerKm: 45, // destination taxis abroad, per km for the group
};

// Per-person, one-way ticket price by mode: max(min, base + perKm * distanceKm).
const TICKET_RATES = {
  flight: { perKm: 2.5, base: 1500, min: 2500 },
  train: { perKm: 1.2, base: 100, min: 250 },
  bus: { perKm: 1.0, base: 80, min: 150 },
  ferry: { perKm: 2.0, base: 200, min: 300 },
};

function round(n) {
  return Math.round(n);
}

function ticketCost(mode, distanceKm, rates = TICKET_RATES) {
  const r = (rates && rates[mode]) || TICKET_RATES[mode];
  if (!r) return 0;
  const km = Number(distanceKm) || 0;
  return Math.max(r.min, r.base + r.perKm * km);
}

/**
 * @param {object} args
 * @param {number} [args.distanceKm] - self-driven distance (alias: driveKm)
 * @param {number} [args.driveKm] - self-driven distance for fuel
 * @param {number} args.estimatedDays
 * @param {object} args.vehicle - { efficiencyKmPerLiter }
 * @param {object|null} args.toll - toll estimate from tollService (may be null)
 * @param {Array<{mode:string,distanceKm:number}>} [args.transportLegs] - flight/train/bus/ferry legs
 * @param {number} [args.localTransportKm] - destination taxi/local-transport distance
 * @param {object} [args.options] - overrides; set options.international=true for outside-India rates
 * @returns {object} budget breakdown
 */
function estimateBudget({
  distanceKm = 0,
  driveKm,
  estimatedDays,
  vehicle,
  toll,
  startLocation = '',
  transportLegs = [],
  localTransportKm = 0,
  ticketRates = TICKET_RATES,
  options = {},
}) {
  const international = !!options.international;
  const base = { ...DEFAULTS, ...(international ? INTL_DEFAULTS : {}) };
  const cfg = { ...base, ...options };
  const days = Math.max(1, estimatedDays || 1);
  const nights = Math.max(0, days - 1);
  const travellers = Math.max(1, cfg.travellers);

  const selfDriveKm = Number(driveKm != null ? driveKm : distanceKm) || 0;

  // Fuel: derive from route distance and current fuel price
  const eff = vehicle && vehicle.efficiencyKmPerLiter > 0 ? vehicle.efficiencyKmPerLiter : 15;
  const fType = (vehicle && vehicle.fuelType) || 'petrol';
  const fuelRequired = selfDriveKm / eff;
  const currentFuel = vehicle && typeof vehicle.currentFuelLiters === 'number' && vehicle.currentFuelLiters >= 0
    ? vehicle.currentFuelLiters
    : 0;
  const additionalFuelRequired = Math.max(0, fuelRequired - currentFuel);
  
  let fuelRate = cfg.fuelPricePerLiter;
  try {
    const prices = fuelService.getFuelPrices({ locationName: startLocation || '', fuelType: fType });
    if (prices.price && prices.price > 0) {
      fuelRate = prices.price;
    }
  } catch (_) {}

  // Estimated fuel expense is based on additional fuel required (or total required if current is 0)
  const fuelCost = Math.round((additionalFuelRequired > 0 ? additionalFuelRequired : fuelRequired) * fuelRate);

  // Tolls: exact fastag cost from authoritative route toll calculation
  let tollCost = 0;
  if (toll && toll.hasTolls) {
    tollCost = toll.fastagTollCost ?? toll.totalAmount ?? toll.minTollCost ?? 0;
  }

  // Transport tickets: flight/train/bus/ferry legs
  let transportCost = 0;
  for (const leg of Array.isArray(transportLegs) ? transportLegs : []) {
    transportCost += ticketCost(leg.mode, leg.distanceKm, ticketRates) * travellers;
  }

  // Local getting-around at the destination (taxis/ride-hail), per group.
  const localTransportCost = (Number(localTransportKm) || 0) * cfg.localTaxiPerKm;

  // Food & Break breakdown (per day, per traveller)
  const breakfastRate = international ? 500 : 250;
  const lunchRate = international ? 1000 : 500;
  const teaSnacksRate = international ? 400 : 200;
  const dinnerRate = international ? 1000 : 500;

  const breakfastCost = breakfastRate * days * travellers;
  const lunchCost = lunchRate * days * travellers;
  const teaSnacksCost = teaSnacksRate * days * travellers;
  const dinnerCost = dinnerRate * days * travellers;
  const foodCost = breakfastCost + lunchCost + teaSnacksCost + dinnerCost;

  const stayCost = cfg.stayPerNight * nights;
  const otherCost = (international ? 800 : 300) * days * travellers;

  const total = fuelCost + tollCost + foodCost + otherCost + transportCost + localTransportCost + stayCost;

  return {
    currency: international ? "USD" : "INR",
    days,
    nights,
    travellers,
    international,
    breakdown: {
      fuel: round(fuelCost),
      tolls: round(tollCost),
      breakfast: round(breakfastCost),
      lunch: round(lunchCost),
      teaSnacks: round(teaSnacksCost),
      dinner: round(dinnerCost),
      food: round(foodCost),
      other: round(otherCost),
      transport: round(transportCost),
      localTransport: round(localTransportCost),
      stay: round(stayCost),
      buffer: round(otherCost),
    },
    total: round(total),
    perDay: round(total / days),
    perPerson: round(total / travellers),
    assumptions: {
      international,
      fuelPricePerLiter: fuelRate,
      fuelRequiredLiters: round(fuelRequired * 10) / 10,
      currentFuelLiters: round(currentFuel * 10) / 10,
      additionalFuelRequiredLiters: round(additionalFuelRequired * 10) / 10,
      breakfastPerDay: breakfastRate,
      lunchPerDay: lunchRate,
      teaSnacksPerDay: teaSnacksRate,
      dinnerPerDay: dinnerRate,
      otherPerDay: international ? 800 : 300,
    },
  };
}

module.exports = { estimateBudget, ticketCost, DEFAULTS, INTL_DEFAULTS, TICKET_RATES };
