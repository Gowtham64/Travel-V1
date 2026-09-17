/// trip_type_utils.dart
///
/// Canonical trip type definitions, normalization, and topology checks for VoyPlan.

class TripTypes {
  static const String oneWay = 'one_way';
  static const String roundTrip = 'round_trip';
  static const String multiDest = 'multi_dest';
  static const String circuit = 'circuit';
  static const String loop = 'loop';
  static const String vacation = 'vacation';

  /// Normalizes any input string to a canonical VoyPlan trip type.
  static String normalize(String? raw) {
    if (raw == null || raw.trim().isEmpty) return roundTrip;
    final clean = raw.toLowerCase().trim().replaceAll(RegExp(r'[\s_-]'), '');

    if (clean == 'oneway' || clean == 'pointtopoint' || clean == 'direct') {
      return oneWay;
    }
    if (clean == 'multidest' ||
        clean == 'multidestination' ||
        clean == 'multistop' ||
        clean == 'multistops' ||
        clean == 'sequential') {
      return multiDest;
    }
    if (clean == 'circuit' || clean == 'circuittrip') {
      return circuit;
    }
    if (clean == 'loop' || clean == 'looptrip') {
      return loop;
    }
    if (clean == 'vacation' ||
        clean == 'vacationtrip' ||
        clean == 'holiday' ||
        clean == 'multiday' ||
        clean == 'itinerary') {
      return vacation;
    }
    if (clean == 'round' ||
        clean == 'roundtrip' ||
        clean == 'around' ||
        clean == 'return') {
      return roundTrip;
    }
    return roundTrip;
  }

  /// Returns true if this trip returns to its origin point.
  static bool isReturnToOrigin(String? raw) {
    final norm = normalize(raw);
    return norm == roundTrip ||
        norm == circuit ||
        norm == loop ||
        norm == vacation;
  }

  /// Returns true if this trip has multiple intermediate stops or destinations.
  static bool isMultiStop(String? raw) {
    final norm = normalize(raw);
    return norm == multiDest ||
        norm == circuit ||
        norm == loop ||
        norm == vacation;
  }

  /// Human-friendly display title
  static String format(String? raw) {
    final norm = normalize(raw);
    switch (norm) {
      case oneWay:
        return 'One Way';
      case roundTrip:
        return 'Round Trip';
      case multiDest:
        return 'Multi-Destination';
      case circuit:
        return 'Circuit';
      case loop:
        return 'Loop';
      case vacation:
        return 'Vacation / Multi-Day';
      default:
        return 'Trip';
    }
  }
}
