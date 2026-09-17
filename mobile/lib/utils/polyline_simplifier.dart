import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

/// Douglas-Peucker polyline simplification algorithm.
/// Reduces coordinate count for long routes based on zoom level.
class PolylineSimplifier {
  /// Simplifies a list of LatLng points using Douglas-Peucker.
  /// [epsilon] is the maximum perpendicular distance in degrees.
  static List<LatLng> simplify(List<LatLng> points, double epsilon) {
    if (points.length <= 2 || epsilon <= 0) return points;

    double maxDistance = 0.0;
    int index = 0;

    final start = points.first;
    final end = points.last;

    for (int i = 1; i < points.length - 1; i++) {
      final d = _perpendicularDistance(points[i], start, end);
      if (d > maxDistance) {
        maxDistance = d;
        index = i;
      }
    }

    if (maxDistance > epsilon) {
      final left = simplify(points.sublist(0, index + 1), epsilon);
      final right = simplify(points.sublist(index), epsilon);
      return [...left.sublist(0, left.length - 1), ...right];
    } else {
      return [start, end];
    }
  }

  /// Returns recommended epsilon tolerance based on Map zoom level (3 to 18).
  /// At low zoom (zoom < 8), simplify more aggressively.
  /// At high zoom (zoom > 13), use minimal or zero simplification.
  static double epsilonForZoom(double zoom) {
    if (zoom <= 6) return 0.008;
    if (zoom <= 9) return 0.003;
    if (zoom <= 12) return 0.0008;
    if (zoom <= 15) return 0.00015;
    return 0.0; // full fidelity at close inspection
  }

  static double _perpendicularDistance(LatLng p, LatLng lineStart, LatLng lineEnd) {
    final dx = lineEnd.longitude - lineStart.longitude;
    final dy = lineEnd.latitude - lineStart.latitude;

    final mag = dx * dx + dy * dy;
    if (mag == 0) {
      final px = p.longitude - lineStart.longitude;
      final py = p.latitude - lineStart.latitude;
      return math.sqrt(px * px + py * py);
    }

    final u = ((p.longitude - lineStart.longitude) * dx + (p.latitude - lineStart.latitude) * dy) / mag;
    final clampedU = u.clamp(0.0, 1.0);

    final nx = lineStart.longitude + clampedU * dx;
    final ny = lineStart.latitude + clampedU * dy;

    final diffX = p.longitude - nx;
    final diffY = p.latitude - ny;
    return math.sqrt(diffX * diffX + diffY * diffY);
  }
}
