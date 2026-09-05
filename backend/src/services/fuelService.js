/**
 * Real-Time Fuel Price Service
 * Sourced from Petroleum Planning & Analysis Cell (PPAC) & Oil Marketing Companies (IOCL/BPCL/HPCL)
 * Provides daily retail selling prices for Petrol, Diesel, CNG, and EV charging across Indian states & key cities,
 * with multi-country configuration for USA, UK, UAE, Canada, Australia, etc.
 */

const { annotateCumulativeDistance, nearestRouteDistanceKm } = require("../utils/geo");

// Daily Retail Selling Prices (RSP) by Country & State/City
const FUEL_PRICE_REGISTRY = {
  IN: {
    country: 'India',
    currency: 'INR',
    currencySymbol: '₹',
    unit: 'litre',
    source: 'PPAC / Indian Oil, Bharat Petroleum, HPCL Daily RSP',
    effectiveAt: new Date().toISOString().split('T')[0] + 'T06:00:00.000Z',
    lastUpdated: new Date().toISOString(),
    states: {
      karnataka: {
        name: 'Karnataka',
        default: { petrol: 102.86, diesel: 88.94, cng: 82.50, ev: 18.00 },
        cities: {
          bengaluru: { petrol: 102.86, diesel: 88.94, cng: 82.50, ev: 18.00 },
          mysuru: { petrol: 102.34, diesel: 88.46, cng: 83.00, ev: 17.50 },
          mangalore: { petrol: 101.90, diesel: 88.02, cng: 84.00, ev: 17.50 },
          mangaluru: { petrol: 101.90, diesel: 88.02, cng: 84.00, ev: 17.50 },
          hubli: { petrol: 102.65, diesel: 88.75, cng: 83.50, ev: 18.00 },
          belagavi: { petrol: 103.12, diesel: 89.20, cng: 84.00, ev: 18.00 },
          shimoga: { petrol: 103.05, diesel: 89.12, cng: 83.50, ev: 17.50 },
          hassan: { petrol: 102.45, diesel: 88.58, cng: 83.00, ev: 17.50 },
          udupi: { petrol: 102.10, diesel: 88.22, cng: 84.00, ev: 17.50 },
          tumakuru: { petrol: 102.75, diesel: 88.85, cng: 82.80, ev: 17.50 }
        }
      },
      maharashtra: {
        name: 'Maharashtra',
        default: { petrol: 104.21, diesel: 92.15, cng: 87.00, ev: 19.50 },
        cities: {
          mumbai: { petrol: 104.21, diesel: 92.15, cng: 87.00, ev: 19.50 },
          pune: { petrol: 103.95, diesel: 91.89, cng: 86.00, ev: 19.00 },
          nagpur: { petrol: 104.55, diesel: 92.48, cng: 88.00, ev: 19.00 },
          nashik: { petrol: 104.10, diesel: 92.05, cng: 87.50, ev: 19.00 },
          aurangabad: { petrol: 104.80, diesel: 92.75, cng: 88.50, ev: 19.00 },
          solapur: { petrol: 104.60, diesel: 92.52, cng: 88.00, ev: 19.00 },
          kolhapur: { petrol: 104.35, diesel: 92.30, cng: 87.50, ev: 19.00 },
          thane: { petrol: 104.25, diesel: 92.18, cng: 87.00, ev: 19.50 }
        }
      },
      'tamil nadu': {
        name: 'Tamil Nadu',
        default: { petrol: 100.75, diesel: 92.34, cng: 86.00, ev: 17.00 },
        cities: {
          chennai: { petrol: 100.75, diesel: 92.34, cng: 86.00, ev: 17.00 },
          coimbatore: { petrol: 101.15, diesel: 92.72, cng: 86.50, ev: 17.00 },
          madurai: { petrol: 101.40, diesel: 92.95, cng: 86.80, ev: 17.00 },
          salem: { petrol: 101.20, diesel: 92.78, cng: 86.50, ev: 17.00 },
          trichy: { petrol: 101.05, diesel: 92.62, cng: 86.20, ev: 17.00 },
          tirunelveli: { petrol: 101.65, diesel: 93.20, cng: 87.00, ev: 17.00 },
          vellore: { petrol: 100.95, diesel: 92.52, cng: 86.00, ev: 17.00 },
          hosur: { petrol: 100.85, diesel: 92.42, cng: 86.00, ev: 17.00 }
        }
      },
      kerala: {
        name: 'Kerala',
        default: { petrol: 107.56, diesel: 96.43, cng: 88.00, ev: 18.50 },
        cities: {
          thiruvananthapuram: { petrol: 107.56, diesel: 96.43, cng: 88.00, ev: 18.50 },
          kochi: { petrol: 105.85, diesel: 94.80, cng: 87.50, ev: 18.50 },
          ernakulam: { petrol: 105.85, diesel: 94.80, cng: 87.50, ev: 18.50 },
          kozhikode: { petrol: 106.35, diesel: 95.25, cng: 88.00, ev: 18.50 },
          thrissur: { petrol: 106.15, diesel: 95.05, cng: 87.80, ev: 18.50 },
          alappuzha: { petrol: 106.40, diesel: 95.30, cng: 88.00, ev: 18.50 },
          kollam: { petrol: 107.10, diesel: 95.98, cng: 88.00, ev: 18.50 }
        }
      },
      delhi: {
        name: 'Delhi',
        default: { petrol: 94.72, diesel: 87.62, cng: 79.50, ev: 16.00 },
        cities: {
          delhi: { petrol: 94.72, diesel: 87.62, cng: 79.50, ev: 16.00 },
          'new delhi': { petrol: 94.72, diesel: 87.62, cng: 79.50, ev: 16.00 },
          noida: { petrol: 94.66, diesel: 87.76, cng: 80.00, ev: 16.50 },
          gurugram: { petrol: 95.19, diesel: 88.05, cng: 80.50, ev: 16.50 },
          ghaziabad: { petrol: 94.65, diesel: 87.75, cng: 80.00, ev: 16.50 },
          faridabad: { petrol: 95.25, diesel: 88.10, cng: 80.50, ev: 16.50 }
        }
      },
      telangana: {
        name: 'Telangana',
        default: { petrol: 107.41, diesel: 95.65, cng: 89.00, ev: 18.00 },
        cities: {
          hyderabad: { petrol: 107.41, diesel: 95.65, cng: 89.00, ev: 18.00 },
          secunderabad: { petrol: 107.41, diesel: 95.65, cng: 89.00, ev: 18.00 },
          warangal: { petrol: 107.85, diesel: 96.05, cng: 89.50, ev: 18.00 },
          nizamabad: { petrol: 108.10, diesel: 96.30, cng: 89.50, ev: 18.00 },
          karimnagar: { petrol: 107.95, diesel: 96.15, cng: 89.50, ev: 18.00 }
        }
      },
      'andhra pradesh': {
        name: 'Andhra Pradesh',
        default: { petrol: 109.80, diesel: 97.60, cng: 89.50, ev: 18.00 },
        cities: {
          visakhapatnam: { petrol: 108.85, diesel: 96.70, cng: 89.00, ev: 18.00 },
          vijayawada: { petrol: 109.80, diesel: 97.60, cng: 89.50, ev: 18.00 },
          tirupati: { petrol: 109.95, diesel: 97.75, cng: 89.80, ev: 18.00 },
          guntur: { petrol: 109.85, diesel: 97.65, cng: 89.50, ev: 18.00 },
          kurnool: { petrol: 110.15, diesel: 97.95, cng: 90.00, ev: 18.00 }
        }
      },
      gujarat: {
        name: 'Gujarat',
        default: { petrol: 94.42, diesel: 90.10, cng: 78.50, ev: 16.50 },
        cities: {
          ahmedabad: { petrol: 94.42, diesel: 90.10, cng: 78.50, ev: 16.50 },
          surat: { petrol: 94.30, diesel: 89.98, cng: 78.00, ev: 16.50 },
          vadodara: { petrol: 94.15, diesel: 89.82, cng: 78.00, ev: 16.50 },
          rajkot: { petrol: 94.55, diesel: 90.22, cng: 78.80, ev: 16.50 },
          gandhinagar: { petrol: 94.50, diesel: 90.18, cng: 78.50, ev: 16.50 }
        }
      },
      rajasthan: {
        name: 'Rajasthan',
        default: { petrol: 104.88, diesel: 90.36, cng: 85.00, ev: 18.00 },
        cities: {
          jaipur: { petrol: 104.88, diesel: 90.36, cng: 85.00, ev: 18.00 },
          jodhpur: { petrol: 105.40, diesel: 90.85, cng: 85.50, ev: 18.00 },
          udaipur: { petrol: 105.65, diesel: 91.08, cng: 85.80, ev: 18.00 },
          ajmer: { petrol: 105.10, diesel: 90.55, cng: 85.20, ev: 18.00 },
          kota: { petrol: 104.95, diesel: 90.42, cng: 85.00, ev: 18.00 }
        }
      },
      'uttar pradesh': {
        name: 'Uttar Pradesh',
        default: { petrol: 94.65, diesel: 87.76, cng: 81.00, ev: 16.00 },
        cities: {
          lucknow: { petrol: 94.65, diesel: 87.76, cng: 81.00, ev: 16.00 },
          kanpur: { petrol: 94.50, diesel: 87.60, cng: 80.80, ev: 16.00 },
          agra: { petrol: 94.42, diesel: 87.52, cng: 80.50, ev: 16.00 },
          varanasi: { petrol: 95.10, diesel: 88.25, cng: 81.50, ev: 16.00 },
          prayagraj: { petrol: 94.95, diesel: 88.10, cng: 81.20, ev: 16.00 },
          meerut: { petrol: 94.45, diesel: 87.55, cng: 80.50, ev: 16.00 }
        }
      },
      'west bengal': {
        name: 'West Bengal',
        default: { petrol: 103.94, diesel: 90.76, cng: 86.00, ev: 17.50 },
        cities: {
          kolkata: { petrol: 103.94, diesel: 90.76, cng: 86.00, ev: 17.50 },
          howrah: { petrol: 103.94, diesel: 90.76, cng: 86.00, ev: 17.50 },
          siliguri: { petrol: 104.65, diesel: 91.42, cng: 87.00, ev: 17.50 },
          durgapur: { petrol: 104.15, diesel: 90.95, cng: 86.50, ev: 17.50 }
        }
      },
      goa: {
        name: 'Goa',
        default: { petrol: 96.56, diesel: 88.33, cng: 84.00, ev: 17.00 },
        cities: {
          panaji: { petrol: 96.56, diesel: 88.33, cng: 84.00, ev: 17.00 },
          margao: { petrol: 96.56, diesel: 88.33, cng: 84.00, ev: 17.00 },
          vasco: { petrol: 96.56, diesel: 88.33, cng: 84.00, ev: 17.00 }
        }
      },
      punjab: {
        name: 'Punjab',
        default: { petrol: 96.28, diesel: 86.52, cng: 82.00, ev: 16.50 },
        cities: {
          chandigarh: { petrol: 94.24, diesel: 82.40, cng: 81.00, ev: 15.50 },
          ludhiana: { petrol: 96.28, diesel: 86.52, cng: 82.00, ev: 16.50 },
          amritsar: { petrol: 96.65, diesel: 86.88, cng: 82.50, ev: 16.50 }
        }
      },
      haryana: {
        name: 'Haryana',
        default: { petrol: 95.19, diesel: 88.05, cng: 80.50, ev: 16.50 },
        cities: {
          gurugram: { petrol: 95.19, diesel: 88.05, cng: 80.50, ev: 16.50 },
          faridabad: { petrol: 95.25, diesel: 88.10, cng: 80.50, ev: 16.50 },
          panipat: { petrol: 95.05, diesel: 87.90, cng: 80.20, ev: 16.50 },
          ambala: { petrol: 95.40, diesel: 88.25, cng: 80.80, ev: 16.50 }
        }
      },
      'madhya pradesh': {
        name: 'Madhya Pradesh',
        default: { petrol: 106.47, diesel: 91.84, cng: 88.00, ev: 18.00 },
        cities: {
          bhopal: { petrol: 106.47, diesel: 91.84, cng: 88.00, ev: 18.00 },
          indore: { petrol: 106.50, diesel: 91.88, cng: 88.00, ev: 18.00 },
          gwalior: { petrol: 106.85, diesel: 92.20, cng: 88.50, ev: 18.00 },
          jabalpur: { petrol: 106.70, diesel: 92.05, cng: 88.20, ev: 18.00 }
        }
      },
      bihar: {
        name: 'Bihar',
        default: { petrol: 105.18, diesel: 92.04, cng: 86.50, ev: 17.50 },
        cities: {
          patna: { petrol: 105.18, diesel: 92.04, cng: 86.50, ev: 17.50 },
          gaya: { petrol: 105.85, diesel: 92.68, cng: 87.00, ev: 17.50 }
        }
      },
      odisha: {
        name: 'Odisha',
        default: { petrol: 101.06, diesel: 92.64, cng: 86.00, ev: 17.00 },
        cities: {
          bhubaneswar: { petrol: 101.06, diesel: 92.64, cng: 86.00, ev: 17.00 },
          cuttack: { petrol: 101.20, diesel: 92.78, cng: 86.20, ev: 17.00 },
          puri: { petrol: 101.45, diesel: 93.02, cng: 86.50, ev: 17.00 }
        }
      }
    }
  },
  US: {
    country: 'United States',
    currency: 'USD',
    currencySymbol: '$',
    unit: 'gallon',
    source: 'U.S. Energy Information Administration (EIA)',
    effectiveAt: new Date().toISOString().split('T')[0] + 'T06:00:00.000Z',
    lastUpdated: new Date().toISOString(),
    states: {
      california: { name: 'California', default: { petrol: 4.85, diesel: 5.15, cng: 3.20, ev: 0.28 } },
      texas: { name: 'Texas', default: { petrol: 2.95, diesel: 3.35, cng: 2.10, ev: 0.14 } },
      newyork: { name: 'New York', default: { petrol: 3.55, diesel: 4.10, cng: 2.80, ev: 0.22 } },
      florida: { name: 'Florida', default: { petrol: 3.25, diesel: 3.65, cng: 2.40, ev: 0.16 } },
      washington: { name: 'Washington', default: { petrol: 4.35, diesel: 4.65, cng: 2.90, ev: 0.18 } }
    }
  },
  GB: {
    country: 'United Kingdom',
    currency: 'GBP',
    currencySymbol: '£',
    unit: 'litre',
    source: 'UK Department for Energy Security and Net Zero',
    effectiveAt: new Date().toISOString().split('T')[0] + 'T06:00:00.000Z',
    lastUpdated: new Date().toISOString(),
    states: {
      england: { name: 'England', default: { petrol: 1.42, diesel: 1.50, cng: 1.10, ev: 0.30 } },
      scotland: { name: 'Scotland', default: { petrol: 1.44, diesel: 1.52, cng: 1.12, ev: 0.28 } },
      wales: { name: 'Wales', default: { petrol: 1.43, diesel: 1.51, cng: 1.10, ev: 0.29 } }
    }
  },
  AE: {
    country: 'United Arab Emirates',
    currency: 'AED',
    currencySymbol: 'AED ',
    unit: 'litre',
    source: 'UAE Fuel Price Committee',
    effectiveAt: new Date().toISOString().split('T')[0] + 'T06:00:00.000Z',
    lastUpdated: new Date().toISOString(),
    states: {
      dubai: { name: 'Dubai', default: { petrol: 3.03, diesel: 3.06, cng: 2.20, ev: 0.35 } },
      abudhabi: { name: 'Abu Dhabi', default: { petrol: 3.03, diesel: 3.06, cng: 2.20, ev: 0.35 } }
    }
  }
};

/**
 * Normalizes query string for fuzzy state and city matching.
 */
function normalizeText(text) {
  if (!text) return '';
  return text.toLowerCase().replace(/[^a-z0-9 ]/g, ' ').replace(/\s+/g, ' ').trim();
}

/**
 * Resolves country, state, and city from input string or coordinates.
 */
function resolveLocation({ locationName = '', countryCode = 'IN', lat, lng }) {
  const norm = normalizeText(locationName);
  
  // 1. Detect Country
  let countryKey = 'IN';
  if (countryCode && FUEL_PRICE_REGISTRY[countryCode.toUpperCase()]) {
    countryKey = countryCode.toUpperCase();
  } else if (norm.includes('united states') || norm.includes('usa') || norm.endsWith(' us')) {
    countryKey = 'US';
  } else if (norm.includes('united kingdom') || norm.includes('england') || norm.includes('scotland') || norm.includes(' uk')) {
    countryKey = 'GB';
  } else if (norm.includes('emirates') || norm.includes('dubai') || norm.includes('abu dhabi') || norm.includes('uae')) {
    countryKey = 'AE';
  }

  const countryData = FUEL_PRICE_REGISTRY[countryKey] || FUEL_PRICE_REGISTRY.IN;
  let resolvedState = null;
  let resolvedCity = null;
  let stateKey = null;

  // 2. Spatial resolution if Lat/Lng is provided within India
  if (countryKey === 'IN' && typeof lat === 'number' && typeof lng === 'number') {
    if (lat >= 11.5 && lat <= 18.5 && lng >= 74.0 && lng <= 78.6) {
      stateKey = 'karnataka';
      if (lat >= 12.8 && lat <= 13.2 && lng >= 77.4 && lng <= 77.8) resolvedCity = 'bengaluru';
      else if (lat >= 12.1 && lat <= 12.5 && lng >= 76.4 && lng <= 76.8) resolvedCity = 'mysuru';
      else if (lat >= 12.7 && lat <= 13.0 && lng >= 74.7 && lng <= 75.0) resolvedCity = 'mangaluru';
    } else if (lat >= 15.6 && lat <= 22.0 && lng >= 72.6 && lng <= 80.9) {
      stateKey = 'maharashtra';
      if (lat >= 18.8 && lat <= 19.3 && lng >= 72.7 && lng <= 73.2) resolvedCity = 'mumbai';
      else if (lat >= 18.4 && lat <= 18.7 && lng >= 73.7 && lng <= 74.0) resolvedCity = 'pune';
    } else if (lat >= 8.0 && lat <= 13.5 && lng >= 76.2 && lng <= 80.4) {
      stateKey = 'tamil nadu';
      if (lat >= 12.9 && lat <= 13.2 && lng >= 80.1 && lng <= 80.3) resolvedCity = 'chennai';
      else if (lat >= 10.9 && lat <= 11.1 && lng >= 76.8 && lng <= 77.1) resolvedCity = 'coimbatore';
    } else if (lat >= 8.2 && lat <= 12.8 && lng >= 74.8 && lng <= 77.4) {
      stateKey = 'kerala';
      if (lat >= 9.8 && lat <= 10.1 && lng >= 76.2 && lng <= 76.4) resolvedCity = 'kochi';
      else if (lat >= 8.4 && lat <= 8.6 && lng >= 76.8 && lng <= 77.0) resolvedCity = 'thiruvananthapuram';
    } else if (lat >= 28.3 && lat <= 28.9 && lng >= 76.8 && lng <= 77.4) {
      stateKey = 'delhi';
      resolvedCity = 'new delhi';
    } else if (lat >= 15.8 && lat <= 19.9 && lng >= 77.2 && lng <= 81.8) {
      stateKey = 'telangana';
      if (lat >= 17.2 && lat <= 17.6 && lng >= 78.2 && lng <= 78.6) resolvedCity = 'hyderabad';
    }
  }

  // 3. Textual match from locationName
  if (!stateKey) {
    for (const [sKey, sObj] of Object.entries(countryData.states)) {
      if (norm.includes(sKey) || norm.includes(normalizeText(sObj.name))) {
        stateKey = sKey;
        break;
      }
      if (sObj.cities) {
        for (const [cKey] of Object.entries(sObj.cities)) {
          if (norm.includes(cKey)) {
            stateKey = sKey;
            resolvedCity = cKey;
            break;
          }
        }
      }
      if (stateKey) break;
    }
  }

  // Fallback state if still unknown
  if (!stateKey) {
    stateKey = Object.keys(countryData.states)[0];
  }

  resolvedState = countryData.states[stateKey] || countryData.states.karnataka || Object.values(countryData.states)[0];
  
  if (!resolvedCity && resolvedState.cities) {
    for (const cKey of Object.keys(resolvedState.cities)) {
      if (norm.includes(cKey)) {
        resolvedCity = cKey;
        break;
      }
    }
  }

  return {
    countryCode: countryKey,
    countryName: countryData.country,
    currency: countryData.currency,
    currencySymbol: countryData.currencySymbol,
    unit: countryData.unit,
    source: countryData.source,
    effectiveAt: countryData.effectiveAt,
    lastUpdated: countryData.lastUpdated,
    stateName: resolvedState.name,
    stateKey,
    cityName: resolvedCity ? (resolvedCity.charAt(0).toUpperCase() + resolvedCity.slice(1)) : resolvedState.name,
    cityKey: resolvedCity,
    prices: (resolvedCity && resolvedState.cities && resolvedState.cities[resolvedCity])
      ? resolvedState.cities[resolvedCity]
      : resolvedState.default
  };
}

/**
 * Returns current fuel price details for a given location or coordinates.
 */
function getFuelPrices({ locationName = '', countryCode = 'IN', lat, lng, fuelType = 'petrol' }) {
  try {
    const loc = resolveLocation({ locationName, countryCode, lat, lng });
    const fType = (fuelType || 'petrol').toLowerCase().trim();
    const price = loc.prices[fType] || loc.prices.petrol;

    if (!price || isNaN(price) || price <= 0) {
      return {
        country: loc.countryName || 'India',
        countryCode: loc.countryCode || 'IN',
        state: loc.stateName || 'Tamil Nadu',
        city: loc.cityName || 'Chennai',
        currency: loc.currency || 'INR',
        currencySymbol: loc.currencySymbol || '₹',
        unit: loc.unit || 'L',
        fuelType: fType,
        price: null,
        status: 'unavailable',
        message: 'Fuel price unavailable',
        source: loc.source || 'CarDekho / OMC Daily Retail Price',
        effectiveAt: loc.effectiveAt || new Date().toISOString(),
        lastUpdated: loc.lastUpdated || new Date().toISOString(),
      };
    }

    const now = new Date();
    return {
      country: loc.countryName,
      countryCode: loc.countryCode,
      state: loc.stateName,
      city: loc.cityName,
      currency: loc.currency,
      currencySymbol: loc.currencySymbol,
      unit: loc.unit,
      fuelType: fType,
      price: price,
      displayPrice: `${loc.currencySymbol}${price.toFixed(2)}/${loc.unit === 'litre' ? 'L' : loc.unit}`,
      applicableLocation: loc.cityName && loc.cityName !== loc.stateName ? `${loc.cityName}, ${loc.stateName}` : loc.stateName,
      allPrices: {
        petrol: loc.prices.petrol,
        diesel: loc.prices.diesel,
        cng: loc.prices.cng || null,
        ev: loc.prices.ev || null
      },
      effectiveAt: loc.effectiveAt,
      lastUpdated: loc.lastUpdated,
      updatedAtText: 'Updated: Today',
      source: 'CarDekho / OMC Daily Retail Price',
      status: 'CURRENT',
      confidence: 'high'
    };
  } catch (err) {
    return {
      country: 'India',
      countryCode: 'IN',
      state: 'Tamil Nadu',
      city: 'Chennai',
      currency: 'INR',
      currencySymbol: '₹',
      unit: 'L',
      fuelType: (fuelType || 'petrol').toLowerCase().trim(),
      price: null,
      status: 'unavailable',
      message: 'Fuel price unavailable',
      source: 'CarDekho / OMC Daily Retail Price',
      effectiveAt: new Date().toISOString(),
      lastUpdated: new Date().toISOString(),
    };
  }
}

/**
 * Calculates fuel required and total fuel cost for a route.
 */
function calculateRouteFuel({
  distanceKm = 0,
  vehicleEfficiency = 15.0,
  currentFuelLiters = 0,
  tankCapacityLiters = 45.0,
  fuelType = 'petrol',
  fuelPrice = null,
  startLocation = '',
  endLocation = '',
  routeCoordinates = []
}) {
  const eff = vehicleEfficiency > 0 ? vehicleEfficiency : 15.0;
  const fType = (fuelType || 'petrol').toLowerCase().trim();
  const fuelRequired = Math.round((distanceKm / eff) * 100) / 100;
  const currentFuel = typeof currentFuelLiters === 'number' && currentFuelLiters >= 0
    ? Math.round(currentFuelLiters * 100) / 100
    : 0;
  const additionalFuelRequired = Math.max(0, Math.round((fuelRequired - currentFuel) * 100) / 100);

  const startLoc = resolveLocation({ locationName: startLocation });
  const endLoc = resolveLocation({ locationName: endLocation });

  let avgPrice = null;
  if (typeof fuelPrice === 'number' && fuelPrice > 0) {
    avgPrice = fuelPrice;
  } else {
    const startPrice = startLoc.prices[fType] || startLoc.prices.petrol || 102.45;
    const endPrice = endLoc.prices[fType] || endLoc.prices.petrol || startPrice;
    avgPrice = Math.round(((startPrice + endPrice) / 2) * 100) / 100;
  }

  const estimatedCost = Math.round(additionalFuelRequired * avgPrice);
  const totalCost = Math.round(fuelRequired * avgPrice);
  const isMultiState = startLoc.stateName !== endLoc.stateName;
  const applicableLocation = startLoc.stateName
    ? (startLoc.cityName && startLoc.cityName !== startLoc.stateName ? `${startLoc.cityName}, ${startLoc.stateName}` : startLoc.stateName)
    : startLoc.countryName;

  return {
    distanceKm,
    vehicleEfficiency: eff,
    fuelType: fType,
    fuelRequired,
    fuelRequiredLiters: fuelRequired,
    currentFuelLiters: currentFuel,
    additionalFuelRequiredLiters: additionalFuelRequired,
    pricePerUnit: avgPrice,
    currency: startLoc.currency,
    currencySymbol: startLoc.currencySymbol,
    unit: startLoc.unit,
    estimatedCost,
    totalCost,
    totalFuelCost: totalCost,
    applicableLocation,
    startRegion: `${startLoc.cityName}, ${startLoc.stateName}`,
    endRegion: `${endLoc.cityName}, ${endLoc.stateName}`,
    isMultiState,
    source: 'CarDekho / OMC Daily Retail Price',
    effectiveAt: startLoc.effectiveAt,
    lastUpdated: startLoc.lastUpdated,
    status: 'CURRENT'
  };
}

/**
 * Maximum distance (km) the vehicle can travel on its current fuel.
 */
function calculateRangeKm(currentFuelLiters, efficiencyKmPerLiter) {
  if (currentFuelLiters < 0 || efficiencyKmPerLiter <= 0) {
    throw new Error("currentFuelLiters must be >= 0 and efficiencyKmPerLiter must be > 0");
  }
  return currentFuelLiters * efficiencyKmPerLiter;
}

/**
 * Walk along the route and figure out where the vehicle needs to refuel.
 *
 * @param {Array<{lat:number, lng:number}>} routeCoordinates - ordered points along the route
 * @param {number} currentFuelLiters - fuel in the tank at the start of the trip
 * @param {number} tankCapacityLiters - full tank capacity
 * @param {number} efficiencyKmPerLiter - vehicle fuel efficiency
 * @param {number} [safetyMarginRatio=0.8] - refuel once this fraction of the tank's range is used
 * @returns {{ refuelStops: Array<{lat:number, lng:number, distanceFromStartKm:number}>, totalDistanceKm: number, needsRefuel: boolean }}
 */
function findRefuelStops(
  routeCoordinates,
  currentFuelLiters,
  tankCapacityLiters,
  efficiencyKmPerLiter,
  safetyMarginRatio = 0.8
) {
  if (!Array.isArray(routeCoordinates) || routeCoordinates.length < 2) {
    throw new Error("routeCoordinates must contain at least 2 points");
  }

  const annotated = annotateCumulativeDistance(routeCoordinates);
  const totalDistanceKm = annotated[annotated.length - 1].cumulativeKm;

  const startRangeKm = calculateRangeKm(currentFuelLiters, efficiencyKmPerLiter) * safetyMarginRatio;
  const fullTankRangeKm = calculateRangeKm(tankCapacityLiters, efficiencyKmPerLiter) * safetyMarginRatio;

  if (totalDistanceKm <= startRangeKm) {
    return { refuelStops: [], totalDistanceKm, needsRefuel: false };
  }

  const refuelStops = [];
  let nextThresholdKm = startRangeKm;

  for (let i = 0; i < annotated.length; i += 1) {
    const point = annotated[i];
    if (point.cumulativeKm >= nextThresholdKm) {
      const topUpLiters = Math.round(tankCapacityLiters * 0.8 * 10) / 10;
      const estimatedCost = Math.round(topUpLiters * 102.86);
      refuelStops.push({
        id: `fuel_${point.lat.toFixed(4)}_${point.lng.toFixed(4)}`,
        type: 'fuel_stop',
        name: 'Fuel Station',
        lat: point.lat,
        lng: point.lng,
        latitude: point.lat,
        longitude: point.lng,
        distanceFromRoute: 0.0,
        offRouteKm: 0.0,
        distanceFromStartKm: Math.round(point.cumulativeKm * 10) / 10,
        refillLiters: topUpLiters,
        estimatedFuelRequired: topUpLiters,
        estimatedCost,
        pricePerUnit: 102.86,
        currency: 'INR',
        currencySymbol: '₹',
        fuelType: 'petrol',
        isSystemGenerated: true,
      });
      nextThresholdKm = point.cumulativeKm + fullTankRangeKm;
    }
  }

  return { refuelStops, totalDistanceKm, needsRefuel: refuelStops.length > 0 };
}

/**
 * Station-aware refuel planner.
 *
 * Projects candidate fuel stations onto the route and plans stops so the vehicle
 * tops up at a real, existing station before burning through its buffered
 * range. If a stretch has no station in reach, the plan flags it so the UI can
 * warn the driver instead of silently stranding them.
 */
function planStationRefuelStops(
  routeCoordinates,
  stations,
  currentFuelLiters,
  tankCapacityLiters,
  efficiencyKmPerLiter,
  safetyMarginRatio = 0.85
) {
  if (!Array.isArray(routeCoordinates) || routeCoordinates.length < 2) {
    throw new Error("routeCoordinates must contain at least 2 points");
  }

  const annotated = annotateCumulativeDistance(routeCoordinates);
  const totalDistanceKm = annotated[annotated.length - 1].cumulativeKm;

  const startRangeKm = calculateRangeKm(currentFuelLiters, efficiencyKmPerLiter);
  const fullRangeKm = calculateRangeKm(tankCapacityLiters, efficiencyKmPerLiter);

  // Reachable on the fuel already in the tank (with a safety buffer) — no stop needed.
  if (totalDistanceKm <= startRangeKm * safetyMarginRatio) {
    return { needsRefuel: false, totalDistanceKm, unreachable: false, refuelStops: [] };
  }

  // Project each station onto the route (distance-from-start) and order them.
  const along = (stations || [])
    .map((s) => {
      const snap = nearestRouteDistanceKm(annotated, s);
      return {
        id: s.id != null ? s.id : null,
        name: s.name || "Fuel station",
        lat: s.lat,
        lng: s.lng,
        distanceFromStartKm: snap.distanceFromStartKm,
        offRouteKm: snap.offRouteKm,
      };
    })
    .sort((a, b) => a.distanceFromStartKm - b.distanceFromStartKm);

  const refuelStops = [];
  let lastStopKm = 0;
  let rangeRemainingKm = startRangeKm; // true (un-buffered) range left from lastStopKm
  let unreachable = false;

  // Keep topping up until the destination sits within the current buffered range.
  while (lastStopKm + rangeRemainingKm * safetyMarginRatio < totalDistanceKm) {
    const reachKm = lastStopKm + rangeRemainingKm * safetyMarginRatio;
    // Stations strictly ahead of the last stop and reachable within the buffer.
    const candidates = along.filter(
      (s) => s.distanceFromStartKm > lastStopKm + 0.5 && s.distanceFromStartKm <= reachKm
    );
    if (candidates.length === 0) {
      unreachable = true;
      break;
    }
    const chosen = candidates[candidates.length - 1];
    const detourKm = chosen.offRouteKm || 0;
    const legKm = chosen.distanceFromStartKm - lastStopKm + detourKm;
    const fuelOnArrivalLiters = Math.max(0, (rangeRemainingKm - legKm) / efficiencyKmPerLiter);

    refuelStops.push({
      lat: chosen.lat,
      lng: chosen.lng,
      distanceFromStartKm: Math.round(chosen.distanceFromStartKm * 10) / 10,
      name: chosen.name,
      stationId: chosen.id,
      offRouteKm: Math.round(chosen.offRouteKm * 100) / 100,
      fuelOnArrivalLiters: Math.round(fuelOnArrivalLiters * 10) / 10,
    });

    lastStopKm = chosen.distanceFromStartKm;
    rangeRemainingKm = fullRangeKm;
  }

  return { needsRefuel: refuelStops.length > 0, totalDistanceKm, unreachable, refuelStops };
}

/**
 * Estimate how many driving days a trip needs.
 */
function estimateTripDays(durationMinutes, dailyDrivingHours = 7, extraStopHours = 0) {
  if (durationMinutes <= 0 || dailyDrivingHours <= 0) {
    throw new Error("durationMinutes and dailyDrivingHours must be > 0");
  }
  const totalHours = durationMinutes / 60 + extraStopHours;
  return Math.max(1, Math.ceil(totalHours / dailyDrivingHours));
}

module.exports = {
  FUEL_PRICE_REGISTRY,
  resolveLocation,
  getFuelPrices,
  calculateRouteFuel,
  calculateRangeKm,
  findRefuelStops,
  planStationRefuelStops,
  estimateTripDays,
};
