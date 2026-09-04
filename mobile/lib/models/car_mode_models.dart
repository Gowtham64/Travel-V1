import 'package:flutter/material.dart';
import 'trip_models.dart';

enum ManeuverType {
  straight,
  turnLeft,
  turnRight,
  slightLeft,
  slightRight,
  sharpLeft,
  sharpRight,
  uTurn,
  forkLeft,
  forkRight,
  roundabout,
  merge,
  offRamp,
  onRamp,
  destination,
  waypoint,
  refuel,
  toll,
}

enum GpsHealthStatus {
  searching,
  active,
  weak,
  lost,
  restored,
}

class LaneInfo {
  final List<String> indications; // 'left', 'straight', 'right', 'slight_left', 'slight_right', 'u_turn'
  final bool valid; // Valid lane for the maneuver
  final bool active; // Optimal / recommended lane
  final String? validIndication;

  const LaneInfo({
    required this.indications,
    this.valid = true,
    this.active = false,
    this.validIndication,
  });

  IconData get icon {
    final primary = (validIndication ?? (indications.isNotEmpty ? indications.first : 'straight')).toLowerCase();
    switch (primary) {
      case 'left':
        return Icons.turn_left_rounded;
      case 'slight_left':
        return Icons.turn_slight_left_rounded;
      case 'sharp_left':
        return Icons.turn_sharp_left_rounded;
      case 'right':
        return Icons.turn_right_rounded;
      case 'slight_right':
        return Icons.turn_slight_right_rounded;
      case 'sharp_right':
        return Icons.turn_sharp_right_rounded;
      case 'u_turn':
        return Icons.u_turn_left_rounded;
      case 'straight':
      default:
        return Icons.straight_rounded;
    }
  }

  factory LaneInfo.fromJson(Map<String, dynamic> json) {
    final ind = (json['indications'] as List?)?.map((e) => e.toString()).toList() ?? ['straight'];
    return LaneInfo(
      indications: ind,
      valid: json['valid'] as bool? ?? true,
      active: json['active'] as bool? ?? false,
      validIndication: json['valid_indication'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'indications': indications,
    'valid': valid,
    'active': active,
    'valid_indication': validIndication,
  };
}

class LaneGuidance {
  final List<LaneInfo> lanes;
  final String? instruction;
  final int recommendedIndex;

  const LaneGuidance({
    required this.lanes,
    this.instruction,
    this.recommendedIndex = 0,
  });

  bool get hasLanes => lanes.isNotEmpty;
}

class ManeuverInstruction {
  final ManeuverType type;
  final String instruction;
  final double distanceMeters;
  final String? roadName;
  final String? secondaryInstruction;
  final LaneGuidance? laneGuidance;
  final double? bearing;
  final String? exitNumber;

  const ManeuverInstruction({
    required this.type,
    required this.instruction,
    required this.distanceMeters,
    this.roadName,
    this.secondaryInstruction,
    this.laneGuidance,
    this.bearing,
    this.exitNumber,
  });

  IconData get icon {
    switch (type) {
      case ManeuverType.turnLeft:
        return Icons.turn_left_rounded;
      case ManeuverType.turnRight:
        return Icons.turn_right_rounded;
      case ManeuverType.slightLeft:
        return Icons.turn_slight_left_rounded;
      case ManeuverType.slightRight:
        return Icons.turn_slight_right_rounded;
      case ManeuverType.sharpLeft:
        return Icons.turn_sharp_left_rounded;
      case ManeuverType.sharpRight:
        return Icons.turn_sharp_right_rounded;
      case ManeuverType.uTurn:
        return Icons.u_turn_left_rounded;
      case ManeuverType.forkLeft:
        return Icons.fork_left_rounded;
      case ManeuverType.forkRight:
        return Icons.fork_right_rounded;
      case ManeuverType.roundabout:
        return Icons.roundabout_right_rounded;
      case ManeuverType.merge:
        return Icons.merge_type_rounded;
      case ManeuverType.offRamp:
        return Icons.ramp_right_rounded;
      case ManeuverType.onRamp:
        return Icons.ramp_left_rounded;
      case ManeuverType.destination:
        return Icons.pin_drop_rounded;
      case ManeuverType.waypoint:
        return Icons.flag_rounded;
      case ManeuverType.refuel:
        return Icons.local_gas_station_rounded;
      case ManeuverType.toll:
        return Icons.toll_rounded;
      case ManeuverType.straight:
      default:
        return Icons.navigation_rounded;
    }
  }

  String get formattedDistance {
    if (distanceMeters >= 1000) {
      return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
    }
    if (distanceMeters <= 20) {
      return 'Now';
    }
    return '${(distanceMeters / 10).round() * 10} m';
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
  final String? upcomingTollName;
  final double? upcomingTollAmount;
  final bool needsRefuel;
  final GpsHealthStatus gpsStatus;
  final bool isRerouting;
  final String speedUnit; // 'km/h' or 'mph'

  const CarTelemetry({
    required this.speedKmh,
    required this.remainingDistanceKm,
    required this.remainingDurationMin,
    required this.progressPercent,
    this.nextStopName,
    this.hasTollAhead = false,
    this.upcomingTollName,
    this.upcomingTollAmount,
    this.needsRefuel = false,
    this.gpsStatus = GpsHealthStatus.active,
    this.isRerouting = false,
    this.speedUnit = 'km/h',
  });

  String get formattedSpeed {
    if (speedUnit == 'mph') {
      final mph = speedKmh * 0.621371;
      return '${mph.round()} mph';
    }
    return '${speedKmh.round()} km/h';
  }

  String get formattedEta {
    final hours = remainingDurationMin ~/ 60;
    final mins = remainingDurationMin % 60;
    if (hours > 0) {
      return '${hours}h ${mins}m';
    }
    return '${mins} min';
  }

  String formattedClockEta({DateTime? fromTime}) {
    final now = fromTime ?? DateTime.now();
    final arrival = now.add(Duration(minutes: remainingDurationMin));
    final h = arrival.hour > 12 ? arrival.hour - 12 : (arrival.hour == 0 ? 12 : arrival.hour);
    final ampm = arrival.hour >= 12 ? 'PM' : 'AM';
    final mm = arrival.minute.toString().padLeft(2, '0');
    return '$h:$mm $ampm';
  }
}
