const { deterministicValidate } = require("../services/geminiValidatorService");

describe("Task 14 & 15: Deterministic Destination Validation Regression Suite", () => {
  // Test 1: Destination = Tirumala
  test("Test 1: Destination = Tirumala accepts Tirumala/Tirupati and rejects distant cities", () => {
    const validTirumalaTrip = {
      days: [
        {
          day: 1,
          blocks: [
            { type: "start", title: "Start Bengaluru", start: "06:00", end: "06:30", lat: 12.9716, lng: 77.5946 },
            { type: "activity", title: "Tirumala Temple", place: "Tirumala Temple", start: "10:00", end: "12:00", lat: 13.6833, lng: 79.3473 },
            { type: "activity", title: "Kapila Theertham", place: "Kapila Theertham", start: "14:00", end: "15:30", lat: 13.6496, lng: 79.4262 },
            { type: "return", title: "Return to Bengaluru", start: "16:00", end: "20:00", lat: 12.9716, lng: 77.5946 },
          ],
        },
      ],
    };

    const passResult = deterministicValidate({
      itinerary: validTirumalaTrip,
      destination: { name: "Tirumala", lat: 13.6833, lng: 79.3473 },
      origin: { name: "Bengaluru", lat: 12.9716, lng: 77.5946 },
    });
    expect(passResult.valid).toBe(true);

    const contaminatedTirumalaTrip = {
      days: [
        {
          day: 1,
          blocks: [
            { type: "start", title: "Start Bengaluru", start: "06:00", end: "06:30", lat: 12.9716, lng: 77.5946 },
            { type: "activity", title: "Tirumala Temple", place: "Tirumala Temple", start: "10:00", end: "12:00", lat: 13.6833, lng: 79.3473 },
            { type: "activity", title: "Mysuru Palace", place: "Mysuru Palace", start: "13:00", end: "14:30", lat: 12.3051, lng: 76.6551 },
            { type: "activity", title: "Marina Beach Chennai", place: "Marina Beach", start: "15:00", end: "16:30", lat: 13.0500, lng: 80.2824 },
          ],
        },
      ],
    };

    const failResult = deterministicValidate({
      itinerary: contaminatedTirumalaTrip,
      destination: { name: "Tirumala", lat: 13.6833, lng: 79.3473 },
      origin: { name: "Bengaluru", lat: 12.9716, lng: 77.5946 },
    });
    expect(failResult.valid).toBe(false);
    expect(failResult.issues.some((i) => i.stop.includes("Mysuru") || i.issue.includes("Mysuru"))).toBe(true);
    expect(failResult.issues.some((i) => i.stop.includes("Chennai") || i.issue.includes("Chennai"))).toBe(true);
  });

  // Test 2: Destination = Goa
  test("Test 2: Destination = Goa accepts Goa locations and rejects Bengaluru, Mumbai, Hyderabad", () => {
    const contaminatedGoaTrip = {
      days: [
        {
          day: 1,
          blocks: [
            { type: "start", title: "Start Panaji", start: "08:00", end: "08:30", lat: 15.4909, lng: 73.8278 },
            { type: "activity", title: "Baga Beach", place: "Baga Beach", start: "09:00", end: "11:00", lat: 15.5553, lng: 73.7517 },
            { type: "activity", title: "Gateway of India Mumbai", place: "Gateway of India Mumbai", start: "12:00", end: "13:30", lat: 18.9220, lng: 72.8347 },
            { type: "activity", title: "Bengaluru Tech Park", place: "Bengaluru Tech Park", start: "14:00", end: "15:30", lat: 12.9716, lng: 77.5946 },
          ],
        },
      ],
    };

    const result = deterministicValidate({
      itinerary: contaminatedGoaTrip,
      destination: { name: "Goa", lat: 15.2993, lng: 74.1240 },
      origin: { name: "Panaji", lat: 15.4909, lng: 73.8278 },
    });
    expect(result.valid).toBe(false);
    expect(result.issues.some((i) => i.issue.includes("Mumbai"))).toBe(true);
    expect(result.issues.some((i) => i.issue.includes("Bengaluru"))).toBe(true);
  });

  // Test 3: Destination = Ooty
  test("Test 3: Destination = Ooty accepts Ooty attractions and rejects Chennai, Bengaluru, Mysuru", () => {
    const contaminatedOotyTrip = {
      days: [
        {
          day: 1,
          blocks: [
            { type: "start", title: "Start Ooty", start: "08:00", end: "08:30", lat: 11.4102, lng: 76.6950 },
            { type: "activity", title: "Ooty Botanical Gardens", place: "Ooty Botanical Gardens", start: "09:00", end: "11:00", lat: 11.4184, lng: 76.7115 },
            { type: "activity", title: "Chennai Marina Mall", place: "Chennai Marina Mall", start: "12:00", end: "13:30", lat: 13.0827, lng: 80.2707 },
          ],
        },
      ],
    };

    const result = deterministicValidate({
      itinerary: contaminatedOotyTrip,
      destination: { name: "Ooty", lat: 11.4102, lng: 76.6950 },
      origin: { name: "Ooty", lat: 11.4102, lng: 76.6950 },
    });
    expect(result.valid).toBe(false);
    expect(result.issues.some((i) => i.issue.includes("Chennai"))).toBe(true);
  });

  // Test 4: Destination = Tirupati
  test("Test 4: Destination = Tirupati accepts Tirupati/nearby attractions and rejects random distant locations", () => {
    const validTirupatiTrip = {
      days: [
        {
          day: 1,
          blocks: [
            { type: "start", title: "Start Tirupati", start: "08:00", end: "08:30", lat: 13.6288, lng: 79.4192 },
            { type: "activity", title: "Sri Govindaraja Swamy Temple", place: "Sri Govindaraja Swamy Temple", start: "09:00", end: "10:30", lat: 13.6335, lng: 79.4184 },
            { type: "activity", title: "Chandragiri Fort", place: "Chandragiri Fort", start: "11:30", end: "13:30", lat: 13.5828, lng: 79.3175 },
          ],
        },
      ],
    };

    const passResult = deterministicValidate({
      itinerary: validTirupatiTrip,
      destination: { name: "Tirupati", lat: 13.6288, lng: 79.4192 },
      origin: { name: "Tirupati", lat: 13.6288, lng: 79.4192 },
    });
    expect(passResult.valid).toBe(true);

    const contaminatedTirupatiTrip = {
      days: [
        {
          day: 1,
          blocks: [
            { type: "start", title: "Start Tirupati", start: "08:00", end: "08:30", lat: 13.6288, lng: 79.4192 },
            { type: "activity", title: "Charminar Hyderabad", place: "Charminar Hyderabad", start: "09:30", end: "11:00", lat: 17.3616, lng: 78.4747 },
          ],
        },
      ],
    };

    const failResult = deterministicValidate({
      itinerary: contaminatedTirupatiTrip,
      destination: { name: "Tirupati", lat: 13.6288, lng: 79.4192 },
      origin: { name: "Tirupati", lat: 13.6288, lng: 79.4192 },
    });
    expect(failResult.valid).toBe(false);
    expect(failResult.issues.some((i) => i.issue.includes("Hyderabad"))).toBe(true);
  });
});
