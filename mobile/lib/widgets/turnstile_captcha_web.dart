// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:js' as js;
import 'package:flutter/material.dart';

/// Flutter Web Cloudflare Turnstile widget.
/// Communicates with the top-level Light DOM Turnstile runner to bypass Shadow DOM restrictions.
class TurnstileCaptcha extends StatefulWidget {
  final String siteKey;
  final ValueChanged<String> onTokenReceived;
  final ValueChanged<String>? onError;

  const TurnstileCaptcha({
    super.key,
    required this.siteKey,
    required this.onTokenReceived,
    this.onError,
  });

  /// Focuses or opens the security challenge centered on the screen.
  static void focusChallenge() {
    try {
      js.context.callMethod('focusCfTurnstile', []);
    } catch (_) {}
  }

  @override
  State<TurnstileCaptcha> createState() => _TurnstileCaptchaState();
}

class _TurnstileCaptchaState extends State<TurnstileCaptcha> {
  late final String _callbackName;
  late final String _errorCallbackName;
  bool _verified = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final uniqueId = DateTime.now().microsecondsSinceEpoch;
    _callbackName = 'onTurnstileSuccess_$uniqueId';
    _errorCallbackName = 'onTurnstileError_$uniqueId';

    // Register JS callback on window for Turnstile token delivery
    js.context[_callbackName] = (String token) {
      if (mounted) {
        setState(() {
          _verified = token.isNotEmpty;
          _errorMessage = null;
        });
        widget.onTokenReceived(token);
      }
    };

    // Register JS callback on window for errors or ad-blocker detection
    js.context[_errorCallbackName] = (String errorReason) {
      if (mounted) {
        setState(() {
          _verified = false;
          _errorMessage = errorReason == 'ADBLOCK_BLOCKED'
              ? 'Security check blocked by browser shield or ad-blocker'
              : 'Security verification failed';
        });
        widget.onError?.call(_errorMessage!);
      }
    };

    // Initialize Turnstile widget on web
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initTurnstile();
    });
  }

  void _initTurnstile() {
    setState(() => _errorMessage = null);
    try {
      js.context.callMethod('initCfTurnstile', [
        widget.siteKey,
        _callbackName,
        _errorCallbackName,
      ]);
    } catch (e) {
      debugPrint('Failed to initialize Turnstile: $e');
    }
  }

  void _openChallengeModal() {
    try {
      js.context.callMethod('focusCfTurnstile', []);
    } catch (_) {}
  }

  @override
  void dispose() {
    try {
      js.context.callMethod('hideCfTurnstile', []);
      js.context.deleteProperty(_callbackName);
      js.context.deleteProperty(_errorCallbackName);
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isBlocked = _errorMessage != null;

    final Color bgColor;
    final Color borderColor;
    final Color iconColor;
    final IconData icon;
    final String label;

    if (_verified) {
      bgColor = const Color(0xFF10B981).withOpacity(0.12);
      borderColor = const Color(0xFF10B981).withOpacity(0.4);
      iconColor = const Color(0xFF10B981);
      icon = Icons.check_circle_rounded;
      label = 'Security check verified ✓';
    } else if (isBlocked) {
      bgColor = const Color(0xFFF59E0B).withOpacity(0.12);
      borderColor = const Color(0xFFF59E0B).withOpacity(0.45);
      iconColor = const Color(0xFFF59E0B);
      icon = Icons.warning_amber_rounded;
      label = 'Shield active. Tap to retry or use Google Sign-in';
    } else {
      bgColor = const Color(0xFF06B6D4).withOpacity(0.08);
      borderColor = const Color(0xFF06B6D4).withOpacity(0.35);
      iconColor = const Color(0xFF06B6D4);
      icon = Icons.shield_outlined;
      label = 'Verifying security check... (Tap to open)';
    }

    return InkWell(
      onTap: _verified
          ? null
          : (isBlocked ? _initTurnstile : _openChallengeModal),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: iconColor, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: _verified
                      ? const Color(0xFF34D399)
                      : (isBlocked
                          ? const Color(0xFFFCD34D)
                          : const Color(0xFF94A3B8)),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (!_verified) ...[
              const SizedBox(width: 6),
              Icon(
                isBlocked ? Icons.refresh_rounded : Icons.open_in_new_rounded,
                color: iconColor.withOpacity(0.8),
                size: 14,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
