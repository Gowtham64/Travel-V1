import 'package:flutter/material.dart';

import '../models/vehicles_data.dart';

/// Loads Vahan Details images with URL-variant retries and a local icon
/// fallback for custom vehicles or unavailable source photos.
class VehicleImage extends StatelessWidget {
  final VehicleModel vehicle;
  final Widget fallback;
  final BoxFit fit;

  const VehicleImage({
    super.key,
    required this.vehicle,
    required this.fallback,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final urls = vehicle.sourceImageUrls;
    if (urls.isEmpty) return fallback;

    Widget load(int index) {
      if (index >= urls.length) return fallback;
      return Image.network(
        urls[index],
        fit: fit,
        errorBuilder: (_, __, ___) => load(index + 1),
      );
    }

    return load(0);
  }
}
