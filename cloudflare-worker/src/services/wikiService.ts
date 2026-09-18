export interface WikiPlace {
  pageid: number;
  title: string;
  lat: number;
  lng: number;
  distanceMeters: number;
  summary: string;
  thumbnailUrl: string | null;
  pageUrl: string;
}

export async function getWikiPlaces(
  lat: number,
  lng: number,
  radiusMeters = 10000,
  limit = 5
): Promise<WikiPlace[]> {
  if (typeof lat !== 'number' || typeof lng !== 'number') {
    return [];
  }

  try {
    const geoUrl = `https://en.wikipedia.org/w/api.php?action=query&list=geosearch&gscoord=${lat}|${lng}&gsradius=${Math.min(
      radiusMeters,
      10000
    )}&gslimit=${limit}&format=json&origin=*`;
    const geoRes = await fetch(geoUrl, { signal: AbortSignal.timeout(8000) });
    if (!geoRes.ok) return [];
    const geoData: any = await geoRes.json();
    const pages = geoData?.query?.geosearch || [];

    if (pages.length === 0) return [];

    const pageIds = pages.map((p: any) => p.pageid).join('|');
    const detailUrl = `https://en.wikipedia.org/w/api.php?action=query&pageids=${pageIds}&prop=pageimages|extracts&pithumbsize=400&exintro=1&explaintext=1&exchars=200&format=json&origin=*`;
    const detailRes = await fetch(detailUrl, { signal: AbortSignal.timeout(8000) });
    if (!detailRes.ok) return [];
    const detailData: any = await detailRes.json();
    const detailPages = detailData?.query?.pages || {};

    return pages.map((p: any) => {
      const info = detailPages[p.pageid] || {};
      return {
        pageid: p.pageid,
        title: p.title,
        lat: p.lat,
        lng: p.lng,
        distanceMeters: Math.round(p.dist),
        summary: info.extract || 'No summary available.',
        thumbnailUrl: info.thumbnail?.source || null,
        pageUrl: `https://en.wikipedia.org/?curid=${p.pageid}`,
      };
    });
  } catch (err: any) {
    console.warn('Wikipedia geosearch failed:', err?.message || err);
    return [];
  }
}
