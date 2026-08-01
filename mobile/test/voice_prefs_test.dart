import 'package:flutter_test/flutter_test.dart';
import 'package:travel_app/services/voice_prefs.dart';

void main() {
  group('bestVoiceIndex', () {
    test('returns -1 for empty list', () {
      expect(bestVoiceIndex([], []), -1);
    });

    test('prefers a Natural/Neural English voice over a plain one', () {
      final names = ['Microsoft David', 'Microsoft Aria Online (Natural)', 'Google Deutsch'];
      final langs = ['en-US', 'en-US', 'de-DE'];
      expect(bestVoiceIndex(names, langs), 1);
    });

    test('picks Google US English when no Natural voice exists', () {
      final names = ['Fred', 'Google US English', 'Albert'];
      final langs = ['en-US', 'en-US', 'en-US'];
      expect(bestVoiceIndex(names, langs), 1);
    });

    test('never picks a non-English voice when an English one exists', () {
      final names = ['Google Nederlands (Natural)', 'Samantha'];
      final langs = ['nl-NL', 'en-US'];
      // "Samantha" (English) must win even though the Dutch one says "Natural".
      expect(bestVoiceIndex(names, langs), 1);
    });

    test('falls back to any English voice when no ranked keyword matches', () {
      final names = ['Xyzzy', 'Zzyar'];
      final langs = ['fr-FR', 'en-GB'];
      expect(bestVoiceIndex(names, langs), 1);
    });

    test('falls back to first voice when none are English', () {
      final names = ['Kyoko', 'Ting-Ting'];
      final langs = ['ja-JP', 'zh-CN'];
      expect(bestVoiceIndex(names, langs), 0);
    });

    test('ranking order: Aria beats Samantha', () {
      final names = ['Samantha', 'Aria'];
      final langs = ['en-US', 'en-US'];
      expect(bestVoiceIndex(names, langs), 1);
    });

    test('pinned voice (Google US English) wins even over a Natural voice', () {
      // Guards the kPreferredVoiceName pin currently set to 'Google US English'.
      final names = ['Microsoft Aria Online (Natural)', 'Google US English'];
      final langs = ['en-US', 'en-US'];
      expect(bestVoiceIndex(names, langs), kPreferredVoiceName == 'Google US English' ? 1 : 0);
    });

    test('is case-insensitive on names and locales', () {
      final names = ['MICROSOFT JENNY ONLINE (NATURAL)'];
      final langs = ['EN-US'];
      expect(bestVoiceIndex(names, langs), 0);
    });
  });
}
