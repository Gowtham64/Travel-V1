import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'dart:js' as js;
import 'package:flutter/material.dart';
import '../models/trip_models.dart';

/// A Mapbox globe (Earth in space) used as the Trip Planner preview. When
/// [focusPoint] becomes non-null (the user picks a start location) the globe
/// stops spinning and flies down to that point.
class GlobePreview extends StatefulWidget {
  final GeoPoint? focusPoint;
  const GlobePreview({super.key, this.focusPoint});

  @override
  State<GlobePreview> createState() => _GlobePreviewState();
}

class _GlobePreviewState extends State<GlobePreview> {
  static const _accessToken =
      'pk.eyJ1IjoiZ293dGhhbWVjNjQiLCJhIjoiY21yZzhnOG82MGh2dTJ6c2FuM3h6ZXdkayJ9.PmiHwk5A4-eSWu7zLYkSXQ';

  late final String _viewType;
  late final String _containerId;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    final id = DateTime.now().microsecondsSinceEpoch;
    _viewType = 'planner-globe-view-$id';
    _containerId = 'planner-globe-container-$id';

    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) => html.DivElement()
        ..id = _containerId
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.backgroundColor = '#080a18',
    );
  }

  void _initGlobe() {
    js.context.callMethod('initPlannerGlobe', [_containerId, _accessToken]);
    // If a start point was already chosen before the globe finished loading,
    // fly to it once the map is ready.
    if (widget.focusPoint != null) {
      Future.delayed(const Duration(milliseconds: 1300), () {
        if (mounted) _flyTo(widget.focusPoint!);
      });
    }
  }

  void _flyTo(GeoPoint p) {
    js.context.callMethod('plannerGlobeFlyTo', [p.lng, p.lat]);
  }

  @override
  void didUpdateWidget(GlobePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final f = widget.focusPoint;
    final old = oldWidget.focusPoint;
    final changed = f != null &&
        (old == null || old.lat != f.lat || old.lng != f.lng);
    if (changed && _initialized) _flyTo(f);
  }

  Widget? _cachedView;

  @override
  Widget build(BuildContext context) {
    _cachedView ??= HtmlElementView(
      viewType: _viewType,
      onPlatformViewCreated: (int id) {
        if (!_initialized) {
          _initialized = true;
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted) _initGlobe();
          });
        }
      },
    );
    return _cachedView!;
  }
}
