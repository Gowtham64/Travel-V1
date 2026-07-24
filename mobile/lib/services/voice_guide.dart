import 'package:flutter_tts/flutter_tts.dart';

/// Cross-platform spoken navigation (Android, iOS, web) via text-to-speech.
/// De-duplicates repeated phrases so it doesn't nag on every GPS tick.
class VoiceGuide {
  final FlutterTts _tts = FlutterTts();
  bool muted = false;

  bool _initialized = false;
  String? _last;
  DateTime? _lastAt;

  Future<void> _ensureInit() async {
    if (_initialized) return;
    _initialized = true;
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(true);
    } catch (_) {/* best-effort; some platforms differ */}
  }

  /// Speaks [text]. Skips if muted, empty, or identical to the last phrase
  /// spoken within [minGapSeconds] (unless [force]).
  Future<void> speak(String text, {bool force = false, int minGapSeconds = 12}) async {
    if (muted || text.trim().isEmpty) return;
    final now = DateTime.now();
    if (!force &&
        _last == text &&
        _lastAt != null &&
        now.difference(_lastAt!).inSeconds < minGapSeconds) {
      return;
    }
    _last = text;
    _lastAt = now;
    await _ensureInit();
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {/* ignore TTS errors */}
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  void reset() {
    _last = null;
    _lastAt = null;
  }

  Future<void> dispose() async {
    await stop();
  }
}
