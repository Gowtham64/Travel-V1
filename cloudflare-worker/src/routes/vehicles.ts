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

const CURATED_VEHICLE_IMAGES: Record<string, string> = {
  // Maruti Suzuki
  'cars:maruti suzuki:swift': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Maruti%20Suzuki/Maruti%20Suzuki%20Swift/Maruti%20Suzuki-Maruti%20Suzuki%20Swift-vahandetails-com1.webp',
  'cars:maruti:swift': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Maruti%20Suzuki/Maruti%20Suzuki%20Swift/Maruti%20Suzuki-Maruti%20Suzuki%20Swift-vahandetails-com1.webp',
  'cars:maruti suzuki:baleno': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Maruti%20Suzuki/Maruti%20Suzuki%20Baleno/Maruti%20Suzuki-Maruti%20Suzuki%20Baleno-vahandetails-com1.webp',
  'cars:maruti:baleno': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Maruti%20Suzuki/Maruti%20Suzuki%20Baleno/Maruti%20Suzuki-Maruti%20Suzuki%20Baleno-vahandetails-com1.webp',
  'cars:maruti suzuki:wagon r': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Maruti%20Suzuki/Maruti%20Suzuki%20WagonR/Maruti%20Suzuki-Maruti%20Suzuki%20WagonR-vahandetails-com1.webp',
  'cars:maruti suzuki:wagonr': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Maruti%20Suzuki/Maruti%20Suzuki%20WagonR/Maruti%20Suzuki-Maruti%20Suzuki%20WagonR-vahandetails-com1.webp',
  'cars:maruti:wagon r': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Maruti%20Suzuki/Maruti%20Suzuki%20WagonR/Maruti%20Suzuki-Maruti%20Suzuki%20WagonR-vahandetails-com1.webp',
  'cars:maruti:wagonr': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Maruti%20Suzuki/Maruti%20Suzuki%20WagonR/Maruti%20Suzuki-Maruti%20Suzuki%20WagonR-vahandetails-com1.webp',
  'cars:maruti suzuki:ertiga': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Maruti%20Suzuki/Maruti%20Suzuki%20Ertiga/Maruti%20Suzuki-Maruti%20Suzuki%20Ertiga-vahandetails-com1.webp',
  'cars:maruti:ertiga': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Maruti%20Suzuki/Maruti%20Suzuki%20Ertiga/Maruti%20Suzuki-Maruti%20Suzuki%20Ertiga-vahandetails-com1.webp',
  'cars:maruti suzuki:dzire': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Maruti%20Suzuki/Maruti%20Suzuki%20Dzire/Maruti%20Suzuki-Maruti%20Suzuki%20Dzire-vahandetails-com1.webp',
  'cars:maruti:dzire': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Maruti%20Suzuki/Maruti%20Suzuki%20Dzire/Maruti%20Suzuki-Maruti%20Suzuki%20Dzire-vahandetails-com1.webp',
  'cars:maruti suzuki:brezza': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Maruti%20Suzuki/Maruti%20Suzuki%20Brezza/Maruti%20Suzuki-Maruti%20Suzuki%20Brezza-vahandetails-com1.webp',
  'cars:maruti:brezza': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Maruti%20Suzuki/Maruti%20Suzuki%20Brezza/Maruti%20Suzuki-Maruti%20Suzuki%20Brezza-vahandetails-com1.webp',
  'cars:maruti suzuki:grand vitara': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Maruti%20Suzuki/Maruti%20Suzuki%20Grand%20Vitara/Maruti%20Suzuki-Maruti%20Suzuki%20Grand%20Vitara-vahandetails-com1.webp',

  // Toyota
  'cars:toyota:innova crysta': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Toyota/Toyota%20Innova%20Crysta/Toyota-Toyota%20Innova%20Crysta-vahandetails-com1.webp',
  'cars:toyota:innova hycross': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Toyota/Toyota%20Innova%20Hycross/Toyota-Toyota%20Innova%20Hycross-vahandetails-com1.webp',
  'cars:toyota:fortuner': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Toyota/Toyota%20Fortuner/Toyota-Toyota%20Fortuner-vahandetails-com1.webp',
  'cars:toyota:urban cruiser hyryder': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Toyota/Toyota%20Urban%20Cruiser%20Hyryder/Toyota-Toyota%20Urban%20Cruiser%20Hyryder-vahandetails-com1.webp',
  'cars:toyota:hyryder': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Toyota/Toyota%20Urban%20Cruiser%20Hyryder/Toyota-Toyota%20Urban%20Cruiser%20Hyryder-vahandetails-com1.webp',

  // Tata Motors
  'cars:tata:nexon': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Tata%20Motors/Tata%20Nexon/Tata%20Motors-Tata%20Nexon-vahandetails-com1.webp',
  'cars:tata motors:nexon': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Tata%20Motors/Tata%20Nexon/Tata%20Motors-Tata%20Nexon-vahandetails-com1.webp',
  'cars:tata:punch': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Tata%20Motors/Tata%20Punch/Tata%20Motors-Tata%20Punch-vahandetails-com1.webp',
  'cars:tata motors:punch': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Tata%20Motors/Tata%20Punch/Tata%20Motors-Tata%20Punch-vahandetails-com1.webp',
  'cars:tata:harrier': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Tata%20Motors/Tata%20Harrier/Tata%20Motors-Tata%20Harrier-vahandetails-com1.webp',
  'cars:tata motors:harrier': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Tata%20Motors/Tata%20Harrier/Tata%20Motors-Tata%20Harrier-vahandetails-com1.webp',
  'cars:tata:safari': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Tata%20Motors/Tata%20Safari/Tata%20Motors-Tata%20Safari-vahandetails-com1.webp',
  'cars:tata motors:safari': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Tata%20Motors/Tata%20Safari/Tata%20Motors-Tata%20Safari-vahandetails-com1.webp',
  'cars:tata:tiago': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Tata%20Motors/Tata%20Tiago/Tata%20Motors-Tata%20Tiago-vahandetails-com1.webp',
  'cars:tata motors:tiago': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Tata%20Motors/Tata%20Tiago/Tata%20Motors-Tata%20Tiago-vahandetails-com1.webp',
  'cars:tata:altroz': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Tata%20Motors/Tata%20Altroz/Tata%20Motors-Tata%20Altroz-vahandetails-com1.webp',
  'cars:tata motors:altroz': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Tata%20Motors/Tata%20Altroz/Tata%20Motors-Tata%20Altroz-vahandetails-com1.webp',
  'cars:tata:nexon ev': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Tata%20Motors/Tata%20Nexon/Tata%20Motors-Tata%20Nexon-vahandetails-com1.webp',
  'cars:tata motors:nexon ev': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Tata%20Motors/Tata%20Nexon/Tata%20Motors-Tata%20Nexon-vahandetails-com1.webp',
  'cars:tata:punch ev': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Tata%20Motors/Tata%20Punch/Tata%20Motors-Tata%20Punch-vahandetails-com1.webp',
  'cars:tata motors:punch ev': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Tata%20Motors/Tata%20Punch/Tata%20Motors-Tata%20Punch-vahandetails-com1.webp',
  'cars:tata:tiago ev': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Tata%20Motors/Tata%20Tiago/Tata%20Motors-Tata%20Tiago-vahandetails-com1.webp',
  'cars:tata motors:tiago ev': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Tata%20Motors/Tata%20Tiago/Tata%20Motors-Tata%20Tiago-vahandetails-com1.webp',

  // Mahindra
  'cars:mahindra:xuv700': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Mahindra/Mahindra%20XUV%20700/Mahindra-Mahindra%20XUV%20700-vahandetails-com1.webp',
  'cars:mahindra:xuv 700': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Mahindra/Mahindra%20XUV%20700/Mahindra-Mahindra%20XUV%20700-vahandetails-com1.webp',
  'cars:mahindra:thar': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Mahindra/Mahindra%20Thar/Mahindra-Mahindra%20Thar-vahandetails-com1.webp',
  'cars:mahindra:scorpio': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Mahindra/Mahindra%20Scorpio/Mahindra-Mahindra%20Scorpio-vahandetails-com1.webp',
  'cars:mahindra:scorpio n': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Mahindra/Mahindra%20Scorpio%20N/Mahindra-Mahindra%20Scorpio%20N-vahandetails-com1.webp',
  'cars:mahindra:scorpio-n': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Mahindra/Mahindra%20Scorpio%20N/Mahindra-Mahindra%20Scorpio%20N-vahandetails-com1.webp',
  'cars:mahindra:bolero': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Mahindra/Mahindra%20Bolero/Mahindra-Mahindra%20Bolero-vahandetails-com1.webp',

  // Hyundai
  'cars:hyundai:creta': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Hyundai/Hyundai%20Creta/Hyundai-Hyundai%20Creta-vahandetails-com1.webp',
  'cars:hyundai:venue': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Hyundai/Hyundai%20Venue/Hyundai-Hyundai%20Venue-vahandetails-com1.webp',
  'cars:hyundai:i20': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Hyundai/Hyundai%20i20/Hyundai-Hyundai%20i20-vahandetails-com1.webp',
  'cars:hyundai:verna': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Hyundai/Hyundai%20Verna/Hyundai-Hyundai%20Verna-vahandetails-com1.webp',

  // Kia
  'cars:kia:seltos': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Kia/Kia%20Seltos/Kia-Kia%20Seltos-vahandetails-com1.webp',
  'cars:kia:sonet': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Kia/Kia%20Sonet/Kia-Kia%20Sonet-vahandetails-com1.webp',
  'cars:kia:carens': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Kia/Kia%20Carens/Kia-Kia%20Carens-vahandetails-com1.webp',

  // Honda
  'cars:honda:city': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Honda/Honda%20City/Honda-Honda%20City-vahandetails-com1.webp',
  'cars:honda:elevate': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Honda/Honda%20Elevate/Honda-Honda%20Elevate-vahandetails-com1.webp',
  'cars:honda:amaze': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Cars/Honda/Honda%20Amaze/Honda-Honda%20Amaze-vahandetails-com1.webp',

  // Royal Enfield
  'bikes:royal enfield:classic 350': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Bikes/Royal%20Enfield/Royal%20Enfield%20Classic%20350/Royal%20Enfield-Royal%20Enfield%20Classic%20350-vahandetails-com1.webp',
  'bikes:royal enfield:bullet 350': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Bikes/Royal%20Enfield/Royal%20Enfield%20Bullet%20350/Royal%20Enfield-Royal%20Enfield%20Bullet%20350-vahandetails-com1.webp',
  'bikes:royal enfield:hunter 350': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Bikes/Royal%20Enfield/Royal%20Enfield%20Hunter%20350/Royal%20Enfield-Royal%20Enfield%20Hunter%20350-vahandetails-com1.webp',
  'bikes:royal enfield:meteor 350': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Bikes/Royal%20Enfield/Royal%20Enfield%20Meteor%20350/Royal%20Enfield-Royal%20Enfield%20Meteor%20350-vahandetails-com1.webp',
  'bikes:royal enfield:continental gt 650': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Bikes/Royal%20Enfield/Royal%20Enfield%20Continental%20GT%20650/Royal%20Enfield-Royal%20Enfield%20Continental%20GT%20650-vahandetails-com1.webp',

  // Bajaj
  'bikes:bajaj:pulsar 150': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Bikes/Bajaj/Bajaj%20Pulsar%20150/Bajaj-Bajaj%20Pulsar%20150-vahandetails-com1.webp',
  'bikes:bajaj auto:pulsar 150': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Bikes/Bajaj/Bajaj%20Pulsar%20150/Bajaj-Bajaj%20Pulsar%20150-vahandetails-com1.webp',
  'bikes:bajaj:pulsar ns200': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Bikes/Bajaj/Bajaj%20Pulsar%20NS200/Bajaj-Bajaj%20Pulsar%20NS200-vahandetails-com1.webp',
  'bikes:bajaj auto:pulsar ns200': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Bikes/Bajaj/Bajaj%20Pulsar%20NS200/Bajaj-Bajaj%20Pulsar%20NS200-vahandetails-com1.webp',
  'bikes:bajaj:dominar 400': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Bikes/Bajaj/Bajaj%20Dominar%20400/Bajaj-Bajaj%20Dominar%20400-vahandetails-com1.webp',
  'bikes:bajaj auto:dominar 400': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Bikes/Bajaj/Bajaj%20Dominar%20400/Bajaj-Bajaj%20Dominar%20400-vahandetails-com1.webp',

  // TVS
  'bikes:tvs:apache rtr 160 4v': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Bikes/TVS/TVS%20Apache%20RTR%20160%204V/TVS-TVS%20Apache%20RTR%20160%204V-vahandetails-com1.webp',
  'bikes:tvs motor:apache rtr 160 4v': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Bikes/TVS/TVS%20Apache%20RTR%20160%204V/TVS-TVS%20Apache%20RTR%20160%204V-vahandetails-com1.webp',
  'bikes:tvs:ronin': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Bikes/TVS/TVS%20Ronin/TVS-TVS%20Ronin-vahandetails-com1.webp',
  'bikes:tvs:ronin 225': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Bikes/TVS/TVS%20Ronin/TVS-TVS%20Ronin-vahandetails-com1.webp',
  'bikes:tvs:jupiter': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Bikes/TVS/TVS%20Jupiter/TVS-TVS%20Jupiter-vahandetails-com1.webp',

  // KTM
  'bikes:ktm:390 duke': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Bikes/KTM/KTM%20390%20Duke/KTM-KTM%20390%20Duke-vahandetails-com1.webp',
  'bikes:ktm:duke 390': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Bikes/KTM/KTM%20390%20Duke/KTM-KTM%20390%20Duke-vahandetails-com1.webp',
  'bikes:ktm:200 duke': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Bikes/KTM/KTM%20200%20Duke/KTM-KTM%20200%20Duke-vahandetails-com1.webp',
  'bikes:ktm:duke 200': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Bikes/KTM/KTM%20200%20Duke/KTM-KTM%20200%20Duke-vahandetails-com1.webp',

  // Suzuki
  'bikes:suzuki:access 125': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Bikes/Suzuki/Suzuki%20Access%20125/Suzuki-Suzuki%20Access%20125-vahandetails-com1.webp',
  'bikes:suzuki:burgman street': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Bikes/Suzuki/Suzuki%20Burgman%20Street/Suzuki-Suzuki%20Burgman%20Street-vahandetails-com1.webp',

  // Honda Bikes
  'bikes:honda:unicorn': 'https://restapi.vahandetails.com/public/Vahandetails_Images/Bikes/Honda/Honda%20Unicorn/Honda-Honda%20Unicorn-vahandetails-com1.webp',
};

async function fetchAndStreamImage(c: any, imageUrl: string) {
  try {
    const res = await fetch(imageUrl, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
        'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
      },
      signal: AbortSignal.timeout(5000),
    });

    if (res.ok && res.body) {
      const contentType = res.headers.get('content-type') || 'image/webp';
      c.header('Content-Type', contentType);
      c.header('Access-Control-Allow-Origin', '*');
      c.header('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
      c.header('Cache-Control', 'public, max-age=604800, stale-while-revalidate=2592000');
      return c.body(res.body);
    }
  } catch (_) {}
  return null;
}

function returnFallbackSvg(c: any, kind: string) {
  const isBike = kind.toLowerCase() === 'bikes' || kind.toLowerCase() === 'motorcycle';

  const svg = isBike
    ? `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 160 100" fill="none">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="160" y2="100" gradientUnits="userSpaceOnUse">
      <stop stop-color="#1E293B"/>
      <stop offset="1" stop-color="#0F172A"/>
    </linearGradient>
    <linearGradient id="g" x1="0" y1="0" x2="160" y2="100" gradientUnits="userSpaceOnUse">
      <stop stop-color="#F59E0B"/>
      <stop offset="1" stop-color="#D97706"/>
    </linearGradient>
  </defs>
  <rect width="160" height="100" rx="14" fill="url(#bg)"/>
  <circle cx="38" cy="62" r="16" fill="#090D16" stroke="#F59E0B" stroke-width="2.5"/>
  <circle cx="38" cy="62" r="5" fill="#F59E0B"/>
  <circle cx="122" cy="62" r="16" fill="#090D16" stroke="#F59E0B" stroke-width="2.5"/>
  <circle cx="122" cy="62" r="5" fill="#F59E0B"/>
  <path d="M38 62 L60 48 L82 48 L104 32 L112 28 M104 32 L122 62 M60 48 L76 62 L98 62 M66 48 L86 38 L98 38 C101 38, 105 41, 103 45 L96 54 L66 54 Z" stroke="url(#g)" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M66 38 C66 33, 76 30, 86 30 C94 30, 99 34, 98 38 Z" fill="url(#g)"/>
  <ellipse cx="124" cy="34" rx="3.5" ry="2.5" fill="#FEF08A"/>
</svg>`
    : `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 160 100" fill="none">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="160" y2="100" gradientUnits="userSpaceOnUse">
      <stop stop-color="#1E293B"/>
      <stop offset="1" stop-color="#0F172A"/>
    </linearGradient>
    <linearGradient id="g" x1="0" y1="0" x2="160" y2="100" gradientUnits="userSpaceOnUse">
      <stop stop-color="#38BDF8"/>
      <stop offset="1" stop-color="#2563EB"/>
    </linearGradient>
  </defs>
  <rect width="160" height="100" rx="14" fill="url(#bg)"/>
  <path d="M18 60 C18 55, 23 52, 30 52 L42 52 C48 52, 54 44, 62 34 C67 28, 75 25, 87 25 L110 25 C118 25, 125 29, 129 36 L139 50 C144 51, 148 55, 148 60 L148 68 C148 71, 145 74, 141 74 L133 74 C132 67, 126 62, 119 62 C112 62, 106 67, 105 74 L57 74 C56 67, 50 62, 43 62 C36 62, 30 67, 29 74 L19 74 C16 74, 18 71, 18 68 Z" fill="url(#g)"/>
  <path d="M63 36 C66 32, 72 29, 78 29 L106 29 C111 29, 117 32, 119 37 L126 48 L56 48 Z" fill="#090D16" opacity="0.88"/>
  <circle cx="43" cy="74" r="11" fill="#090D16" stroke="#38BDF8" stroke-width="2.5"/>
  <circle cx="43" cy="74" r="5" fill="#38BDF8"/>
  <circle cx="119" cy="74" r="11" fill="#090D16" stroke="#38BDF8" stroke-width="2.5"/>
  <circle cx="119" cy="74" r="5" fill="#38BDF8"/>
  <ellipse cx="142" cy="58" rx="4" ry="2.5" fill="#FEF08A"/>
</svg>`;

  c.header('Content-Type', 'image/svg+xml; charset=utf-8');
  c.header('Access-Control-Allow-Origin', '*');
  c.header('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
  c.header('Cache-Control', 'public, max-age=604800, stale-while-revalidate=2592000');
  return c.body(svg);
}

// Vehicle model image resolver with CORS proxy and high-resolution fallback
vehicles.get('/image', async (c) => {
  const brand = String(c.req.query('brand') || '').trim();
  const model = String(c.req.query('model') || '').trim();
  const kind = String(c.req.query('type') || '').toLowerCase() === 'motorcycle' ? 'Bikes' : 'Cars';

  if (!brand || !model) {
    return c.json({ error: 'brand and model are required' }, 400);
  }

  const baseModel = model
    .replace(/\s+(reborn|facelift|edition|series|classic|strong hybrid|hybrid|alpha\+|plus|pro|max)\b/gi, '')
    .trim();

  const lookupKeys = [
    `${kind.toLowerCase()}:${brand.toLowerCase()}:${model.toLowerCase()}`,
    `${kind.toLowerCase()}:${brand.toLowerCase()}:${baseModel.toLowerCase()}`,
  ];

  for (const lookupKey of lookupKeys) {
    const curatedUrl = CURATED_VEHICLE_IMAGES[lookupKey];
    if (curatedUrl) {
      const res = await fetchAndStreamImage(c, curatedUrl);
      if (res) return res;
    }
  }

  const cacheKey = imageCacheKey(kind, brand, model);
  const cached = imageCache.get(cacheKey);

  if (cached && cached.expiresAt > Date.now()) {
    if (cached.url) {
      const res = await fetchAndStreamImage(c, cached.url);
      if (res) return res;
    }
  }

  const brandVariants = new Set<string>([brand]);
  const bLower = brand.toLowerCase();
  if (bLower === 'tata motors' || bLower === 'tata') brandVariants.add('Tata Motors').add('Tata');
  if (bLower === 'maruti suzuki' || bLower === 'maruti') brandVariants.add('Maruti Suzuki').add('Maruti');
  if (bLower.includes('mg')) brandVariants.add('MG Motor').add('MG Motors').add('MG');
  if (bLower.includes('hero')) brandVariants.add('Hero MotoCorp').add('Hero');
  if (bLower.includes('bajaj')) brandVariants.add('Bajaj Auto').add('Bajaj');
  if (bLower.includes('tvs')) brandVariants.add('TVS Motor').add('TVS');

  const cleanModel = model.replace(/\.ev$/i, ' EV').replace(/\./g, '');
  const modelVariants = new Set<string>([
    cleanModel,
    model,
    model.replace(/\s+/g, ''),
    model.replace(/([a-zA-Z]+)(\d+)/g, '$1 $2'),
    model.replace(/([a-zA-Z]+)\s+(\d+)/g, '$1$2'),
  ]);

  const candidates: string[] = [];
  for (const b of brandVariants) {
    for (const m of modelVariants) {
      const folders = [m, `${b} ${m}`];
      const prefixes = [`${b}-${m}`, `${b}-${b} ${m}`];
      for (const folder of folders) {
        for (const prefix of prefixes) {
          candidates.push(
            `https://restapi.vahandetails.com/public/Vahandetails_Images/${kind}/${encodeURIComponent(b)}/${encodeURIComponent(folder)}/${encodeURIComponent(`${prefix}-vahandetails-com1.webp`)}`
          );
        }
      }
    }
  }

  for (const candidateUrl of candidates) {
    try {
      const checkRes = await fetch(candidateUrl, {
        method: 'HEAD',
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
        },
        signal: AbortSignal.timeout(2500),
      });

      if (checkRes.status >= 200 && checkRes.status < 300) {
        rememberImage(cacheKey, candidateUrl, IMAGE_CACHE_TTL_MS);
        const streamed = await fetchAndStreamImage(c, candidateUrl);
        if (streamed) return streamed;
      }
    } catch (_) {}
  }

  // Graceful fallback SVG ensures UI never shows broken image or blank container
  return returnFallbackSvg(c, kind);
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
