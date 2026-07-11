# Travel app - mobile (Flutter)

A minimal but functional screen flow:
1. **Home screen** - enter start/destination addresses and vehicle details
2. **Trip screen** - map with the route, refuel stops, and nearby places, plus a summary card

## Setup

This needs the Flutter SDK installed locally (this couldn't be built/run in the sandbox
that generated this code, so double-check `flutter pub get` resolves cleanly).

```bash
cd mobile
flutter pub get
flutter run
```

## Connecting to the backend

`lib/services/api_service.dart` defaults to `http://localhost:3000`. Update this depending
on where you're running things:

- **iOS simulator**: `http://localhost:3000` works as-is
- **Android emulator**: use `http://10.0.2.2:3000` (the emulator's alias for your host machine)
- **Physical device**: use your computer's LAN IP, e.g. `http://192.168.1.50:3000`, and make
  sure your phone is on the same network as the backend

```dart
final api = ApiService(baseUrl: 'http://10.0.2.2:3000');
```

## What's built vs. what's next

Built:
- Address input → geocoding → route planning → results screen
- Map rendering with `flutter_map` (OpenStreetMap tiles, no API key)
- Refuel stop markers, POI markers (fuel/hotel/restaurant/attraction)
- Trip summary: distance, duration, estimated days, fuel needs, toll estimate

Not yet built (see the main project README's phased plan):
- Saving/persisting trips
- Multi-stop itinerary editing (reordering, removing suggested stops)
- Offline map caching
- Proper location picker (map-tap or "use my current location") instead of typed addresses only
- Loading/empty/error states polish
