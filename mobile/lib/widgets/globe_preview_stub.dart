import 'package:flutter/material.dart';
import '../models/trip_models.dart';

/// Non-web fallback. The globe is a web-only Mapbox feature; on other
/// platforms this renders a plain dark space-colored surface.
class GlobePreview extends StatelessWidget {
  final GeoPoint? focusPoint;
  const GlobePreview({super.key, this.focusPoint});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(color: Color(0xFF080A18));
  }
}
