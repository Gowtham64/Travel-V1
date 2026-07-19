/**
 * Estimate a full trip budget (fuel + tolls + food + stay + a small buffer).
 *
 * The routing/fuel/toll services already give us the hard numbers; this layer
 * adds the "human" costs of a multi-day road trip so the user sees a single
 * all-in figure instead of just fuel and tolls.
 *
 * All figures are India-focused and in INR. Per-person/per-day rates are rough
 * mid-range defaults and can be overridden by the caller.
 */

const DEFAULTS = {
  fuelPricePerLiter: 102, // INR, petrol-ish national average
  foodPerDay: 600, // per person, 3 meals mid-range
  stayPerNight: 1800, // mid-range hotel room
  travellers: 1,
  bufferRatio: 0.1, // 10% miscellaneous buffer (parking, snacks, etc.)
};

function round(n) {
  return Math.round(n);
}

/**
 * @param {object} args
 * @param {number} args.distanceKm
 * @param {number} args.estimatedDays
 * @param {object} args.vehicle - { efficiencyKmPerLiter }
 * @param {object|null} args.toll - toll estimate from tollService (may be null)
 * @param {object} [args.options] - overrides for the DEFAULTS above
 * @returns {object} budget breakdown
 */
function estimateBudget({ distanceKm, estimatedDays, vehicle, toll, options = {} }) {
  const cfg = { ...DEFAULTS, ...options };
  const days = Math.max(1, estimatedDays || 1);
  const nights = Math.max(0, days - 1);
  const travellers = Math.max(1, cfg.travellers);

  // Fuel: prefer a fuel cost already computed upstream, otherwise derive it.
  const eff = vehicle && vehicle.efficiencyKmPerLiter > 0 ? vehicle.efficiencyKmPerLiter : 15;
  const liters = distanceKm / eff;
  const fuelCost =
    toll && typeof toll.fuelCost === "number" && toll.fuelCost > 0
      ? toll.fuelCost
      : liters * cfg.fuelPricePerLiter;

  // Tolls: use the FASTag figure when available, else the min estimate.
  let tollCost = 0;
  if (toll && toll.hasTolls) {
    tollCost = toll.fastagTollCost ?? toll.minTollCost ?? 0;
  }

  const foodCost = cfg.foodPerDay * days * travellers;
  const stayCost = cfg.stayPerNight * nights;

  const subtotal = fuelCost + tollCost + foodCost + stayCost;
  const buffer = subtotal * cfg.bufferRatio;
  const total = subtotal + buffer;

  return {
    currency: "INR",
    days,
    nights,
    travellers,
    breakdown: {
      fuel: round(fuelCost),
      tolls: round(tollCost),
      food: round(foodCost),
      stay: round(stayCost),
      buffer: round(buffer),
    },
    total: round(total),
    perDay: round(total / days),
    perPerson: round(total / travellers),
    assumptions: {
      fuelPricePerLiter: cfg.fuelPricePerLiter,
      foodPerDayPerPerson: cfg.foodPerDay,
      stayPerNight: cfg.stayPerNight,
      bufferRatio: cfg.bufferRatio,
    },
  };
}

module.exports = { estimateBudget, DEFAULTS };
