import seedPrices from '../data/prices.json';

const DAY_MS = 24 * 60 * 60 * 1000;

export interface PriceTable {
  updatedAt: string | null;
  fxUpdatedAt: string | null;
  source: string;
  fx: { usdToInr: number };
  fuel: { petrolPerLiter: number; dieselPerLiter: number };
  tollPerKm: number;
  foodPerDay: number;
  stayPerNight: number;
  localTaxiPerKm: number;
  ticketRates: {
    flight: { perKm: number; base: number; min: number };
    train: { perKm: number; base: number; min: number };
    bus: { perKm: number; base: number; min: number };
    ferry: { perKm: number; base: number; min: number };
  };
  intlUsd: {
    foodPerDay: number;
    stayPerNight: number;
    localTaxiPerKm: number;
  };
  intl: {
    foodPerDay: number;
    stayPerNight: number;
    localTaxiPerKm: number;
  };
}

function seed(): PriceTable {
  return {
    updatedAt: (seedPrices as any).updatedAt || null,
    fxUpdatedAt: (seedPrices as any).fxUpdatedAt || null,
    source: 'seed',
    fx: { usdToInr: (seedPrices as any).fx?.usdToInr || 88 },
    fuel: {
      petrolPerLiter: (seedPrices as any).fuel?.petrolPerLiter || 102,
      dieselPerLiter: (seedPrices as any).fuel?.dieselPerLiter || 90,
    },
    tollPerKm: (seedPrices as any).tollPerKm || 0.7,
    foodPerDay: (seedPrices as any).foodPerDay || 600,
    stayPerNight: (seedPrices as any).stayPerNight || 1800,
    localTaxiPerKm: (seedPrices as any).localTaxiPerKm || 18,
    ticketRates: (seedPrices as any).ticketRates || {
      flight: { perKm: 2.5, base: 1500, min: 2500 },
      train: { perKm: 1.2, base: 100, min: 250 },
      bus: { perKm: 1.0, base: 80, min: 150 },
      ferry: { perKm: 2.0, base: 200, min: 300 },
    },
    intlUsd: (seedPrices as any).intlUsd || {
      foodPerDay: 30,
      stayPerNight: 80,
      localTaxiPerKm: 0.55,
    },
    intl: { foodPerDay: 0, stayPerNight: 0, localTaxiPerKm: 0 },
  };
}

let prices: PriceTable = recomputeIntl(seed());
let refreshingPromise: Promise<PriceTable> | null = null;

function recomputeIntl(p: PriceTable): PriceTable {
  const fx = p.fx.usdToInr || 88;
  p.intl = {
    foodPerDay: Math.round(p.intlUsd.foodPerDay * fx),
    stayPerNight: Math.round(p.intlUsd.stayPerNight * fx),
    localTaxiPerKm: Math.round(p.intlUsd.localTaxiPerKm * fx),
  };
  return p;
}

async function fetchUsdInr(): Promise<number | null> {
  try {
    const res = await fetch('https://open.er-api.com/v6/latest/USD', {
      signal: AbortSignal.timeout(8000),
    });
    if (!res.ok) return null;
    const data: any = await res.json();
    const inr = data && data.rates && Number(data.rates.INR);
    return Number.isFinite(inr) && inr > 0 ? inr : null;
  } catch (_) {
    return null;
  }
}

export async function refresh(): Promise<PriceTable> {
  if (refreshingPromise) return refreshingPromise;
  refreshingPromise = (async () => {
    const nowIso = new Date().toISOString();
    const inr = await fetchUsdInr();
    if (inr) {
      prices.fx.usdToInr = Math.round(inr * 100) / 100;
      prices.fxUpdatedAt = nowIso;
      prices.source = 'live-fx';
    }
    recomputeIntl(prices);
    prices.updatedAt = nowIso;
    refreshingPromise = null;
    return prices;
  })();
  return refreshingPromise;
}

export function isStale(): boolean {
  if (!prices.updatedAt) return true;
  return Date.now() - new Date(prices.updatedAt).getTime() > DAY_MS;
}

export function getRates(): PriceTable {
  if (isStale() && !refreshingPromise) {
    refresh().catch(() => {});
  }
  return prices;
}

export default {
  getRates,
  refresh,
  isStale,
  seed,
};
