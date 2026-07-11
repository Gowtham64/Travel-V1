const { findPOIsAlongRoute } = require('./src/services/orsPoiService');
(async () => {
  try {
    const routeCoordinates = [
      { lat: 13.0827, lng: 80.2707 },
      { lat: 11.0168, lng: 76.9558 }
    ];
    const categories = ['fuel'];
    const places = await findPOIsAlongRoute(routeCoordinates, categories);
    console.log(JSON.stringify(places, null, 2));
  } catch (err) {
    console.error(err);
  }
})();
