import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'dart:js' as js;
import 'package:flutter/material.dart';

/// Flutter Web Cloudflare Turnstile widget.
/// Renders the official Turnstile verification widget into a registered HTML platform view.
class TurnstileCaptcha extends StatefulWidget {
  final String siteKey;
  final ValueChanged<String> onTokenReceived;

  const TurnstileCaptcha({
    super.key,
    required this.siteKey,
    required this.onTokenReceived,
  });

  @override
  State<TurnstileCaptcha> createState() => _TurnstileCaptchaState();
}

class _TurnstileCaptchaState extends State<TurnstileCaptcha> {
  late final String _viewType;
  late final String _containerId;
  late final String _callbackName;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    final uniqueId = DateTime.now().microsecondsSinceEpoch;
    _viewType = 'cf-turnstile-view-$uniqueId';
    _containerId = 'cf-turnstile-container-$uniqueId';
    _callbackName = 'onTurnstileSuccess_$uniqueId';

    // Register JS callback on window for Turnstile token delivery
    js.context[_callbackName] = (String token) {
      if (mounted) {
        widget.onTokenReceived(token);
      }
    };

    // Register HTML view factory with Flutter Web engine
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) {
        final container = html.DivElement()
          ..id = _containerId
          ..style.width = '300px'
          ..style.minHeight = '65px'
          ..style.display = 'flex'
          ..style.alignItems = 'center'
          ..style.justifyContent = 'center';

        // Trigger rendering once attached to DOM
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted && !_initialized) {
            _initialized = true;
            _renderTurnstile();
          }
        });

        return container;
      },
    );
  }

  void _renderTurnstile() {
    try {
      js.context.callMethod('renderCfTurnstile', [
        _containerId,
        widget.siteKey,
        _callbackName,
      ]);
    } catch (e) {
      debugPrint('Failed to render Turnstile: $e');
    }
  }

  @override
  void dispose() {
    try {
      js.context.callMethod('resetCfTurnstile', []);
      js.context.deleteProperty(_callbackName);
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 300,
        height: 70,
        alignment: Alignment.center,
        child: HtmlElementView(viewType: _viewType),
      ),
    );
  }
}
