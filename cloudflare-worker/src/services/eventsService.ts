export interface DestinationEvent {
  id: string;
  title: string;
  category: string;
  location: string;
  date: string;
  description: string;
  url: string | null;
}

export async function getDestinationEvents(
  lat: number,
  lng: number,
  destinationName = ''
): Promise<DestinationEvent[]> {
  if (typeof lat !== 'number' || typeof lng !== 'number') {
    return [];
  }

  const events: DestinationEvent[] = [];

  // Try Ticketmaster public API if search term available
  if (destinationName) {
    try {
      const query = encodeURIComponent(destinationName);
      const url = `https://app.ticketmaster.com/discovery/v2/events.json?keyword=${query}&size=4&apikey=7elgEcT9TXA8oM4PGzA20tBfaA`;
      const res = await fetch(url, { signal: AbortSignal.timeout(5000) });
      if (res.ok) {
        const data: any = await res.json();
        const tmEvents = data?._embedded?.events || [];
        for (const ev of tmEvents) {
          events.push({
            id: ev.id || String(Math.random()),
            title: ev.name,
            category: ev.classifications?.[0]?.segment?.name || 'General Event',
            location: ev._embedded?.venues?.[0]?.name || destinationName,
            date: ev.dates?.start?.localDate || 'Upcoming',
            description: ev.info || `Event in ${destinationName}`,
            url: ev.url || null,
          });
        }
      }
    } catch (_) {}
  }

  // Fallback: search Wikipedia events or local highlights near coordinates
  if (events.length === 0) {
    try {
      const wikiUrl = `https://en.wikipedia.org/w/api.php?action=query&list=geosearch&gscoord=${lat}|${lng}&gsradius=10000&gslimit=5&format=json&origin=*`;
      const wikiRes = await fetch(wikiUrl, { signal: AbortSignal.timeout(5000) });
      if (wikiRes.ok) {
        const wikiData: any = await wikiRes.json();
        const spots = wikiData?.query?.geosearch || [];
        for (const spot of spots.slice(0, 3)) {
          events.push({
            id: `wiki-${spot.pageid}`,
            title: `Explore ${spot.title}`,
            category: 'Sightseeing & Culture',
            location: destinationName || 'Near Destination',
            date: 'Open Daily',
            description: `Popular cultural point of interest located ${Math.round(spot.dist)}m from center.`,
            url: `https://en.wikipedia.org/?curid=${spot.pageid}`,
          });
        }
      }
    } catch (_) {}
  }

  return events;
}
