// Reading experience: dark/light mode, font size and style, spacing, and the
// page-turner (default) vs scroll view.
import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:free_book_reader/reader/reader_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// WCAG 2.x contrast ratio between two colors.
double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  group('defaults', () {
    const settings = ReaderSettings();
    test('start in page-turner view', () => expect(settings.viewMode, ViewMode.pageTurner));
    test('start in light mode', () => expect(settings.theme, ReaderTheme.light));
    test('readable starting sizes', () {
      expect(settings.fontSize, 18);
      expect(settings.lineHeight, 1.5);
      expect(settings.letterSpacing, 0);
      expect(settings.paragraphSpacing, 1.0);
      expect(settings.fontFamily, ReaderFont.serif);
    });
  });

  group('limits', () {
    test('font size is clamped to 12..40', () {
      expect(const ReaderSettings(fontSize: 2).fontSize, 12);
      expect(const ReaderSettings(fontSize: 99).fontSize, 40);
      expect(const ReaderSettings().copyWith(fontSize: 100).fontSize, 40);
    });

    test('line height is clamped to 1.0..2.5', () {
      expect(const ReaderSettings(lineHeight: 0.2).lineHeight, 1.0);
      expect(const ReaderSettings(lineHeight: 9).lineHeight, 2.5);
    });

    test('letter spacing is clamped to 0..0.2', () {
      expect(const ReaderSettings(letterSpacing: -1).letterSpacing, 0);
      expect(const ReaderSettings(letterSpacing: 5).letterSpacing, 0.2);
    });

    test('paragraph spacing is clamped to 0..3', () {
      expect(const ReaderSettings(paragraphSpacing: -1).paragraphSpacing, 0);
      expect(const ReaderSettings(paragraphSpacing: 10).paragraphSpacing, 3);
    });
  });

  group('copyWith', () {
    test('changes only the named setting', () {
      final changed = const ReaderSettings().copyWith(theme: ReaderTheme.dark);
      expect(changed.theme, ReaderTheme.dark);
      expect(changed.fontSize, 18);
      expect(changed.viewMode, ViewMode.pageTurner);
    });

    test('settings with the same values are equal', () {
      expect(const ReaderSettings(fontSize: 20), const ReaderSettings(fontSize: 20));
      expect(const ReaderSettings(fontSize: 20).hashCode,
          const ReaderSettings(fontSize: 20).hashCode);
      expect(const ReaderSettings(fontSize: 20), isNot(const ReaderSettings(fontSize: 22)));
    });
  });

  group('fonts', () {
    test('there is a choice of styles including one for dyslexia', () {
      expect(ReaderFont.values,
          containsAll([ReaderFont.serif, ReaderFont.sansSerif, ReaderFont.dyslexiaFriendly]));
    });

    test('each style has a name a screen reader can say', () {
      for (final font in ReaderFont.values) {
        expect(font.label, isNotEmpty);
      }
    });
  });

  group('colors meet WCAG 2.2 AA', () {
    for (final theme in ReaderTheme.values) {
      test('${theme.name}: body text has at least 4.5:1 contrast', () {
        final settings = ReaderSettings(theme: theme);
        expect(contrast(settings.textColor, settings.backgroundColor), greaterThanOrEqualTo(4.5));
      });
    }

    test('dark mode is actually dark and light mode is light', () {
      expect(const ReaderSettings(theme: ReaderTheme.dark).backgroundColor.computeLuminance(),
          lessThan(0.2));
      expect(const ReaderSettings(theme: ReaderTheme.light).backgroundColor.computeLuminance(),
          greaterThan(0.8));
    });
  });

  group('text style', () {
    test('applies size, line height and letter spacing', () {
      final style = const ReaderSettings(fontSize: 24, lineHeight: 2.0, letterSpacing: 0.1).textStyle;
      expect(style.fontSize, 24);
      expect(style.height, 2.0);
      expect(style.letterSpacing, closeTo(2.4, 1e-9)); // em -> logical pixels
      expect(style.color, const ReaderSettings().textColor);
    });
  });

  group('persistence', () {
    Future<ReaderSettingsStore> store([Map<String, Object> initial = const {}]) async {
      SharedPreferences.setMockInitialValues(initial);
      return ReaderSettingsStore(await SharedPreferences.getInstance());
    }

    test('a new device gets the defaults', () async {
      expect((await store()).load(), const ReaderSettings());
    });

    test('settings round-trip', () async {
      final s = await store();
      const custom = ReaderSettings(
        theme: ReaderTheme.dark,
        fontSize: 26,
        fontFamily: ReaderFont.dyslexiaFriendly,
        lineHeight: 1.9,
        letterSpacing: 0.05,
        paragraphSpacing: 2,
        viewMode: ViewMode.scroll,
      );
      await s.save(custom);
      expect(s.load(), custom);
    });

    test('corrupt stored values fall back to defaults', () async {
      final s = await store({'reader_settings': '{not json'});
      expect(s.load(), const ReaderSettings());
    });

    test('unknown stored enum values fall back to defaults', () async {
      final s = await store({'reader_settings': '{"theme":"sepia","viewMode":"swipe"}'});
      expect(s.load().theme, ReaderTheme.light);
      expect(s.load().viewMode, ViewMode.pageTurner);
    });
  });
}
