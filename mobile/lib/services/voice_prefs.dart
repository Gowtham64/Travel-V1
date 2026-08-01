/// Shared, platform-independent logic for choosing a soft, natural-sounding
/// navigation voice. Kept free of dart:html / flutter_tts so it can be unit
/// tested directly.

/// Force a specific platform voice by (case-insensitive substring of its) name,
/// e.g. 'Google US English', 'Microsoft Aria Online (Natural)', 'Samantha'.
/// Leave null to auto-pick the smoothest available voice.
const String? kPreferredVoiceName = 'Google US English';

/// Voice-name keywords ranked most → least preferred for a calm, smooth,
/// human-sounding voice. "Natural"/"Neural"/named cloud voices first; the
/// generic 'female' fallback is last.
const List<String> kSoftVoiceRanking = [
  'natural',
  'neural',
  'aria',
  'jenny',
  'libby',
  'sonia',
  'michelle',
  'emma',
  'ava',
  'samantha',
  'serena',
  'moira',
  'google us english',
  'google uk english female',
  'female',
];

/// Picks the index of the best voice from parallel [names]/[langs] lists.
///
/// Order of preference:
///  1. [kPreferredVoiceName] (if set and present),
///  2. an English voice matching the highest-ranked keyword in
///     [kSoftVoiceRanking],
///  3. any English voice,
///  4. the first voice.
///
/// Returns -1 only when the lists are empty.
int bestVoiceIndex(List<String> names, List<String> langs) {
  final n = names.length;
  if (n == 0) return -1;

  String nameAt(int i) => names[i].toLowerCase();
  String langAt(int i) => (i < langs.length ? langs[i] : '').toLowerCase();
  bool isEnglish(int i) => langAt(i).startsWith('en');

  // 1. Explicit pin wins if we can find it (prefer an English match).
  final pin = kPreferredVoiceName?.toLowerCase();
  if (pin != null && pin.isNotEmpty) {
    int fallback = -1;
    for (var i = 0; i < n; i++) {
      if (nameAt(i).contains(pin)) {
        if (isEnglish(i)) return i;
        if (fallback < 0) fallback = i;
      }
    }
    if (fallback >= 0) return fallback;
  }

  // 2. Highest-ranked keyword among English voices.
  for (final key in kSoftVoiceRanking) {
    for (var i = 0; i < n; i++) {
      if (isEnglish(i) && nameAt(i).contains(key)) return i;
    }
  }

  // 3. Any English voice.
  for (var i = 0; i < n; i++) {
    if (isEnglish(i)) return i;
  }

  // 4. Anything.
  return 0;
}
