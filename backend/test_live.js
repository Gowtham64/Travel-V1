const axios = require('axios');
(async () => {
  try {
    const payload = {
      start: { lat: 13.0827, lng: 80.2707 },
      end: { lat: 11.0168, lng: 76.9558 },
      waypoints: [ { lat: 76.952441, lng: 11.021623 } ], // Swapped on purpose
      vehicle: {
        type: 'car',
        efficiencyKmPerLiter: 15,
        tankCapacityLiters: 40,
        currentFuelLiters: 10
      }
    };
    const res = await axios.post('https://travel-v1-mzia.onrender.com/api/trip/plan', payload);
    console.log("Success:", res.data.distanceKm);
  } catch (err) {
    console.error("Error:", err.response ? err.response.data : err.message);
  }
})();
