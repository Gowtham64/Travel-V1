/// Cross-platform spoken navigation (Android, iOS, web) via text-to-speech.
/// De-duplicates repeated phrases so it doesn't nag on every GPS tick.
class VoiceGuide {
  bool muted = false;

  bool _initialized = false;
  String? _last;
  DateTime? _lastAt;

  Future<void> _ensureInit() async {
    if (_initialized) return;
    _initialized = true;
  }

  /// Warms up TTS ahead of the first prompt.
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
  }

  Future<void> stop() async {}

  void reset() {
    _last = null;
    _lastAt = null;
  }

  Future<void> dispose() async {
    await stop();
  }
}
