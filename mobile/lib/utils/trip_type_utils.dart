/// trip_type_utils.dart
///
/// Canonical trip type definitions, normalization, and topology checks for VoyPlan.
library trip_type_utils;

class TripTypes {
  static const String oneWay = 'one_way';
  static const String vacation = 'vacation';
  // Legacy alias pointing to consolidated vacation
  static const String roundTrip = 'vacation';
  static const String multiDest = 'vacation';
  static const String circuit = 'vacation';
  static const String loop = 'vacation';

  /// Normalizes any input string to a canonical VoyPlan trip type (strictly one_way or vacation).
  static String normalize(String? raw) {
    if (raw == null || raw.trim().isEmpty) return oneWay;
    final clean = raw.toLowerCase().trim().replaceAll(RegExp(r'[\s_-]'), '');

    if (clean == 'oneway' || clean == 'pointtopoint' || clean == 'direct') {
      return oneWay;
    }
    // Any multi-day, round trip, return, circuit or vacation is consolidated into vacation
    return vacation;
  }

  /// Returns true if this trip returns to its origin point.
  static bool isReturnToOrigin(String? raw) {
    final norm = normalize(raw);
    return norm == vacation;
  }

  /// Returns true if this trip has multiple intermediate stops or destinations.
  static bool isMultiStop(String? raw) {
    final norm = normalize(raw);
    return norm == vacation;
  }

  /// Human-friendly display title
  static String format(String? raw) {
    final norm = normalize(raw);
    switch (norm) {
      case oneWay:
        return 'One Way';
      case vacation:
        return 'Vacation';
      default:
        return 'One Way';
    }
  }
}
