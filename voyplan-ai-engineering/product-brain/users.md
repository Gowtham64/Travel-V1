# VoyPlan — User Personas & Problem Space

## 1. Primary User Personas

### Persona A: The Pilgrimage & Family Traveler ("Ramesh & Sunita")
- **Profile**: Traveling with multi-generational family (elders + children) to sacred destinations (e.g. Tirumala, Madurai, Varanasi).
- **Core Needs**: Predictable morning darshan timings, nearby genuine temple stops (not commercial restaurants masquerading as shrines), minimal exhaustion, verified restrooms and food.
- **Pain Point**: Generic AI tools recommend Bangalore cafes or distant hill stations when planning a pilgrimage to Tirumala.

### Persona B: The Weekend Roadtripper ("Arjun")
- **Profile**: 28-year-old software engineer driving from Bengaluru to Ooty, Coorg, or Goa for a 3-day weekend.
- **Core Needs**: High-speed scenic routes, fuel refill stops, toll cost estimation, CarPlay/Android Auto navigation, drag-and-drop itinerary editing.
- **Pain Point**: Disconnected navigation apps require switching between Maps, fuel calculators, and notes.

### Persona C: The EV Explorer ("Priya")
- **Profile**: Driving an electric vehicle (Tata Nexon EV / MG ZS EV).
- **Core Needs**: Reliable charging stop planning along highway corridors with minimum detour time.

---

## 2. Key User Problems Solved
1. **Hallucinated Distant Stops**: Solved deterministically via coordinate bounding (<75km) and forbidden city cluster rejection.
2. **Disconnected Budgeting**: Solved via integrated toll (FASTag) and fuel prediction APIs.
3. **In-Car Disconnection**: Solved via native Android Auto `CarNavState.kt` and iOS CarPlay `CarPlayVoiceGuidance.swift` bridges.
