import 'dart:js' as js;
import 'package:flutter/material.dart';

/// Flutter Web Cloudflare Turnstile widget.
/// Communicates with the top-level Light DOM Turnstile runner to bypass Shadow DOM restrictions.
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
  late final String _callbackName;
  bool _verified = false;

  @override
  void initState() {
    super.initState();
    final uniqueId = DateTime.now().microsecondsSinceEpoch;
    _callbackName = 'onTurnstileSuccess_$uniqueId';

    // Register JS callback on window for Turnstile token delivery
    js.context[_callbackName] = (String token) {
      if (mounted) {
        setState(() => _verified = token.isNotEmpty);
        widget.onTokenReceived(token);
      }
    };

    // Initialize Turnstile widget on web
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initTurnstile();
    });
  }

  void _initTurnstile() {
    try {
      js.context.callMethod('initCfTurnstile', [
        widget.siteKey,
        _callbackName,
      ]);
    } catch (e) {
      debugPrint('Failed to initialize Turnstile: $e');
    }
  }

  @override
  void dispose() {
    try {
      js.context.callMethod('hideCfTurnstile', []);
      js.context.deleteProperty(_callbackName);
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _verified
            ? const Color(0xFF10B981).withOpacity(0.12)
            : const Color(0xFF0F172A).withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _verified
              ? const Color(0xFF10B981).withOpacity(0.35)
              : const Color(0xFF06B6D4).withOpacity(0.35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _verified
                ? Icons.check_circle_rounded
                : Icons.shield_outlined,
            color: _verified
                ? const Color(0xFF10B981)
                : const Color(0xFF06B6D4),
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            _verified
                ? 'Security check completed'
                : 'Cloudflare Turnstile active',
            style: TextStyle(
              color: _verified
                  ? const Color(0xFF34D399)
                  : const Color(0xFF94A3B8),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
