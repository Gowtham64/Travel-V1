const { getRoute } = require('./src/services/routingService');
(async () => {
  try {
    const start = { lat: 13.0827, lng: 80.2707 };
    const end = { lat: 11.0168, lng: 76.9558 };
    const waypoints = [ { lat: 11.021623, lng: 76.952441 } ];
    const route = await getRoute(start, end, waypoints);
    console.log("Success! Distance:", route.distanceKm);
  } catch (err) {
    console.error("Error:", err.response ? err.response.data : err.message);
  }
})();
