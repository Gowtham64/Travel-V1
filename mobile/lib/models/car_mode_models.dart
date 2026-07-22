import 'package:flutter/material.dart';
import 'trip_models.dart';

enum ManeuverType {
  straight,
  turnLeft,
  turnRight,
  slightLeft,
  slightRight,
  uTurn,
  destination,
  refuel,
  toll,
}

class ManeuverInstruction {
  final ManeuverType type;
  final String instruction;
  final double distanceMeters;
  final String? roadName;

  const ManeuverInstruction({
    required this.type,
    required this.instruction,
    required this.distanceMeters,
    this.roadName,
  });

  IconData get icon {
    switch (type) {
      case ManeuverType.turnLeft:
        return Icons.turn_left;
      case ManeuverType.turnRight:
        return Icons.turn_right;
      case ManeuverType.slightLeft:
        return Icons.turn_slight_left;
      case ManeuverType.slightRight:
        return Icons.turn_slight_right;
      case ManeuverType.uTurn:
        return Icons.u_turn_left;
      case ManeuverType.destination:
        return Icons.pin_drop;
      case ManeuverType.refuel:
        return Icons.local_gas_station;
      case ManeuverType.toll:
        return Icons.toll;
      case ManeuverType.straight:
      default:
        return Icons.navigation;
    }
  }

  String get formattedDistance {
    if (distanceMeters >= 1000) {
      return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
    }
    return '${distanceMeters.round()} m';
  }
}

/// A single maneuver at a fixed point along the route, with its distance from
/// the route start. The ordered list of these drives the CarPlay / Android Auto
/// upcoming-steps list (which is computed ahead of time, not just live).
class RouteStep {
  final ManeuverInstruction maneuver;
  final GeoPoint location;
  final double distanceFromStartMeters;

  const RouteStep({
    required this.maneuver,
    required this.location,
    required this.distanceFromStartMeters,
  });
}

class CarTelemetry {
  final double speedKmh;
  final double remainingDistanceKm;
  final int remainingDurationMin;
  final double progressPercent;
  final String? nextStopName;
  final bool hasTollAhead;
  final bool needsRefuel;

  const CarTelemetry({
    required this.speedKmh,
    required this.remainingDistanceKm,
    required this.remainingDurationMin,
    required this.progressPercent,
    this.nextStopName,
    this.hasTollAhead = false,
    this.needsRefuel = false,
  });

  String get formattedEta {
    final hours = remainingDurationMin ~/ 60;
    final mins = remainingDurationMin % 60;
    if (hours > 0) {
      return '${hours}h ${mins}m';
    }
    return '${mins} min';
  }
}
