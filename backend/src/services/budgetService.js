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
  transportLegs = [],
  localTransportKm = 0,
  ticketRates = TICKET_RATES,
  options = {},
}) {
  const international = !!options.international;
  // International rates apply as the baseline abroad, but any explicit override
  // in `options` still wins.
  const base = { ...DEFAULTS, ...(international ? INTL_DEFAULTS : {}) };
  const cfg = { ...base, ...options };
  const days = Math.max(1, estimatedDays || 1);
  const nights = Math.max(0, days - 1);
  const travellers = Math.max(1, cfg.travellers);

  const selfDriveKm = Number(driveKm != null ? driveKm : distanceKm) || 0;

  // Fuel: prefer a fuel cost already computed upstream, otherwise derive dynamically.
  const eff = vehicle && vehicle.efficiencyKmPerLiter > 0 ? vehicle.efficiencyKmPerLiter : 15;
  const fType = (vehicle && vehicle.fuelType) || 'petrol';
  const liters = selfDriveKm / eff;
  
  let fuelRate = cfg.fuelPricePerLiter;
  try {
    const prices = fuelService.getFuelPrices({ locationName: start || '', fuelType: fType });
    fuelRate = prices.price || fuelRate;
  } catch (_) {}

  const fuelCost =
    toll && typeof toll.fuelCost === "number" && toll.fuelCost > 0
      ? toll.fuelCost
      : Math.round(liters * fuelRate);

  // Tolls: use the FASTag figure when available, else the min estimate.
  let tollCost = 0;
  if (toll && toll.hasTolls) {
    tollCost = toll.fastagTollCost ?? toll.minTollCost ?? 0;
  }

  // Transport tickets: flight/train/bus/ferry legs, priced per person per leg.
  let transportCost = 0;
  for (const leg of Array.isArray(transportLegs) ? transportLegs : []) {
    transportCost += ticketCost(leg.mode, leg.distanceKm, ticketRates) * travellers;
  }

  // Local getting-around at the destination (taxis/ride-hail), per group.
  const localTransportCost = (Number(localTransportKm) || 0) * cfg.localTaxiPerKm;

  const foodCost = cfg.foodPerDay * days * travellers;
  const stayCost = cfg.stayPerNight * nights;

  const subtotal =
    fuelCost + tollCost + transportCost + localTransportCost + foodCost + stayCost;
  const buffer = subtotal * cfg.bufferRatio;
  const total = subtotal + buffer;

  return {
    currency: "INR",
    days,
    nights,
    travellers,
    international,
    breakdown: {
      fuel: round(fuelCost),
      tolls: round(tollCost),
      transport: round(transportCost),
      localTransport: round(localTransportCost),
      food: round(foodCost),
      stay: round(stayCost),
      buffer: round(buffer),
    },
    total: round(total),
    perDay: round(total / days),
    perPerson: round(total / travellers),
    assumptions: {
      international,
      fuelPricePerLiter: cfg.fuelPricePerLiter,
      foodPerDayPerPerson: cfg.foodPerDay,
      stayPerNight: cfg.stayPerNight,
      localTaxiPerKm: cfg.localTaxiPerKm,
      bufferRatio: cfg.bufferRatio,
    },
  };
}

module.exports = { estimateBudget, ticketCost, DEFAULTS, INTL_DEFAULTS, TICKET_RATES };
