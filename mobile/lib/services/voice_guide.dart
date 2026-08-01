import 'package:flutter_tts/flutter_tts.dart';
import 'voice_prefs.dart';

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
      // Softer, smoother delivery: unhurried pace, slightly lower pitch, and a
      // gently reduced volume so guidance sounds calm rather than robotic.
      await _tts.setSpeechRate(0.46);
      await _tts.setVolume(0.9);
      await _tts.setPitch(0.96);
      await _tts.awaitSpeakCompletion(true);
      await _selectSoftVoice();
    } catch (_) {/* best-effort; some platforms differ */}
  }

  /// Picks a natural/neural English voice when the platform offers one, for a
  /// warmer, smoother sound than the default robotic voice. Voice lists load
  /// asynchronously (especially on web), so retry a few times before giving up.
  Future<void> _selectSoftVoice() async {
    for (var attempt = 0; attempt < 6; attempt++) {
      try {
        final raw = await _tts.getVoices;
        if (raw is List) {
          final voices = raw.whereType<Map>().toList();
          if (voices.isNotEmpty) {
            final names = voices.map((v) => '${v['name'] ?? ''}').toList();
            final langs = voices.map((v) => '${v['locale'] ?? ''}').toList();
            final idx = bestVoiceIndex(names, langs);
            if (idx >= 0) {
              final best = voices[idx];
              await _tts.setVoice({
                'name': '${best['name']}',
                'locale': '${best['locale'] ?? 'en-US'}',
              });
              return;
            }
          }
        }
      } catch (_) {/* voice list unavailable on some platforms */}
      await Future.delayed(const Duration(milliseconds: 250));
    }
  }

  /// Warms up TTS + the voice list ahead of the first prompt so it doesn't
  /// briefly speak in the default robotic voice.
  Future<void> prime() => _ensureInit();

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
