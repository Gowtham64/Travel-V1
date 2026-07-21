import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/trip_models.dart';
import '../services/api_service.dart';

class MapLocationPickerScreen extends StatefulWidget {
  final LatLng? initialCenter;
  final String label;

  const MapLocationPickerScreen({
    super.key,
    this.initialCenter,
    required this.label,
  });

  @override
  State<MapLocationPickerScreen> createState() => _MapLocationPickerScreenState();
}

class _MapLocationPickerScreenState extends State<MapLocationPickerScreen> {
  final _mapController = MapController();
  final _api = ApiService();

  LatLng? _selectedPoint;
  String? _resolvedAddress;
  bool _isResolving = false;
  LatLng _mapCenter = const LatLng(12.9716, 77.5946); // Default: Bangalore

  @override
  void initState() {
    super.initState();
    if (widget.initialCenter != null) {
      _mapCenter = widget.initialCenter!;
      _selectedPoint = widget.initialCenter!;
      _reverseGeocode(_selectedPoint!);
    } else {
      _centerOnCurrentLocation(initial: true);
    }
  }

  Future<void> _centerOnCurrentLocation({bool initial = false}) async {
    try {
      if (kIsWeb) {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );
        final currentLatLng = LatLng(position.latitude, position.longitude);
        if (mounted) {
          setState(() {
            _mapCenter = currentLatLng;
            if (initial && widget.initialCenter == null) {
              _selectedPoint = currentLatLng;
              _reverseGeocode(currentLatLng);
            }
          });
          _mapController.move(currentLatLng, 15.0);
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );
        final currentLatLng = LatLng(position.latitude, position.longitude);
        if (mounted) {
          setState(() {
            _mapCenter = currentLatLng;
            if (initial && widget.initialCenter == null) {
              _selectedPoint = currentLatLng;
              _reverseGeocode(currentLatLng);
            }
          });
          _mapController.move(currentLatLng, 15.0);
        }
      }
    } catch (e) {
      debugPrint('Error getting current location: $e');
      if (!initial && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not determine current location: $e')),
        );
      }
    }
  }

  Future<void> _reverseGeocode(LatLng point) async {
    setState(() {
      _isResolving = true;
      _resolvedAddress = null;
    });

    try {
      final address = await _api.reverseGeocode(point.latitude, point.longitude);
      if (mounted) {
        setState(() {
          _resolvedAddress = address;
        });
      }
    } catch (e) {
      debugPrint('Reverse geocoding error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isResolving = false;
        });
      }
    }
  }

  Widget _buildGlassCard({required Widget child, EdgeInsetsGeometry padding = const EdgeInsets.all(24.0)}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.08),
                Colors.white.withOpacity(0.02),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
          ),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. The Map View
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _mapCenter,
              initialZoom: 13.0,
              onTap: (tapPosition, point) {
                setState(() {
                  _selectedPoint = point;
                });
                _reverseGeocode(point);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.travel_app',
              ),
              if (_selectedPoint != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _selectedPoint!,
                      width: 50,
                      height: 50,
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.location_on,
                            color: Colors.redAccent,
                            size: 40,
                            shadows: [
                              Shadow(
                                blurRadius: 8.0,
                                color: Colors.black45,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // 2. Translucent Custom App Bar Overlay
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            right: 16,
            child: _buildGlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Choose ${widget.label}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 3. Floating GPS Center Button
          Positioned(
            bottom: 220,
            right: 16,
            child: FloatingActionButton(
              onPressed: () => _centerOnCurrentLocation(),
              backgroundColor: const Color(0xFF2E75B6),
              foregroundColor: Colors.white,
              elevation: 4,
              shape: const CircleBorder(),
              child: const Icon(Icons.my_location),
            ),
          ),

          // 4. Bottom Glass Panel for Confirmation
          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: _buildGlassCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_selectedPoint == null)
                    const Center(
                      child: Text(
                        'Tap anywhere on the map to set a pin',
                        style: TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                    )
                  else ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.pin_drop, color: Colors.redAccent, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_isResolving)
                                const Row(
                                  children: [
                                    SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    ),
                                    SizedBox(width: 10),
                                    Text(
                                      'Locating address...',
                                      style: TextStyle(color: Colors.white70, fontSize: 14),
                                    ),
                                  ],
                                )
                              else
                                Text(
                                  _resolvedAddress ?? 'Unknown Location',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              const SizedBox(height: 6),
                              Text(
                                '${_selectedPoint!.latitude.toStringAsFixed(5)}, ${_selectedPoint!.longitude.toStringAsFixed(5)}',
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () {
                        final lat = _selectedPoint!.latitude;
                        final lng = _selectedPoint!.longitude;
                        final displayName = _resolvedAddress ?? '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
                        Navigator.of(context).pop(
                          GeoPoint(lat: lat, lng: lng, name: displayName),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E75B6),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Confirm Location',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
