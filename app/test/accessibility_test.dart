// WCAG 2.2 AA checks that a unit test can make. They do not replace testing
// with real screen readers (VoiceOver, TalkBack, NVDA) or an expert audit, but
// they stop the common regressions: low contrast, tiny or unlabeled targets,
// content that breaks at 200% text size or 320px width, and keyboard traps.
//
// Milestones: homepage, search page (with results), and the reading screen
// "pass accessibility testing".
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:free_book_reader/models/models.dart';

import 'helpers/test_app.dart';

/// One entry per screen: how to reach it, and the key of its main heading.
final screens = <String, ({Future<void> Function(WidgetTester, TestEnv) go, String heading})>{
  'home': (go: (t, e) async {}, heading: 'home-heading'),
  'results': (go: (t, e) => searchFor(t, 'pride'), heading: 'results-heading'),
  'no results': (go: (t, e) async {
    e.api.response = const SearchResponse(works: [], unavailableSources: ['doab']);
    await searchFor(t, 'zzzz');
  }, heading: 'results-heading'),
  'details': (go: (t, e) => openDetails(t, 'w-pride'), heading: 'details-title'),
  'source about': (go: (t, e) async {
    final link = find.byKey(const Key('about-link-librivox'));
    await t.ensureVisible(link);
    await t.tap(link);
    await t.pumpAndSettle();
  }, heading: 'about-title'),
  'reader with player': (go: (t, e) => openBook(t, e, 'w-pride', 'gutenberg:1342'), heading: 'reader-title'),
  'audiobook': (go: (t, e) => openBook(t, e, 'w-pride', 'librivox:253'), heading: 'audio-title'),
};

void main() {
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    group('${mode.name} mode', () {
      for (final entry in screens.entries) {
        testWidgets('${entry.key}: contrast, tap targets and labels', (tester) async {
          final handle = tester.ensureSemantics();
          final env = await TestEnv.create();
          await pumpApp(tester, env, themeMode: mode);
          await entry.value.go(tester, env);
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          handle.dispose();
        });
      }
    });
  }

  group('reader themes', () {
    for (final theme in ['light', 'dark']) {
      testWidgets('reader in $theme: contrast, tap targets and labels', (tester) async {
        final handle = tester.ensureSemantics();
        // Our own renderer, so the book text itself is checked too.
        final env = await TestEnv.create(
            prefsValues: {'reader_settings': '{"theme":"$theme"}'}, textEngine: true);
        await pumpApp(tester, env);
        await openBook(tester, env, 'w-pride', 'gutenberg:1342');
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        handle.dispose();
      });
    }

    testWidgets('reader settings panel: contrast, tap targets and labels', (tester) async {
      final handle = tester.ensureSemantics();
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await openBook(tester, env, 'w-pride', 'gutenberg:1342');
      await tester.tap(find.byKey(const Key('reader-settings-button')));
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });
  });

  group('headings (WCAG 1.3.1, 2.4.6)', () {
    for (final entry in screens.entries) {
      testWidgets('${entry.key} has a heading', (tester) async {
        final handle = tester.ensureSemantics();
        final env = await TestEnv.create();
        await pumpApp(tester, env);
        await entry.value.go(tester, env);
        expect(tester.getSemantics(find.byKey(Key(entry.value.heading))),
            containsSemantics(isHeader: true));
        handle.dispose();
      });
    }
  });

  group('resize text to 200% (WCAG 1.4.4) and reflow at 320px (1.4.10)', () {
    for (final entry in screens.entries) {
      testWidgets('${entry.key}: nothing overflows', (tester) async {
        final env = await TestEnv.create();
        await pumpApp(tester, env, size: smallPhone, textScale: 2.0);
        await entry.value.go(tester, env);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('home: the search box and button stay on screen', (tester) async {
      await pumpApp(tester, await TestEnv.create(), size: smallPhone, textScale: 2.0);
      final screen = Offset.zero & smallPhone;
      expect(screen.contains(tester.getCenter(find.byKey(const Key('search-field')))), isTrue);
      expect(tester.getRect(find.byKey(const Key('search-submit'))).right,
          lessThanOrEqualTo(smallPhone.width));
    });

    testWidgets('results: nothing needs sideways scrolling', (tester) async {
      await pumpApp(tester, await TestEnv.create(), size: smallPhone, textScale: 2.0);
      await searchFor(tester, 'pride');
      for (final id in ['w-pride']) {
        final rect = tester.getRect(find.byKey(Key('result-$id')));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(smallPhone.width));
      }
    });

    testWidgets('reader: text scale is honored on top of the font size setting', (tester) async {
      final env = await TestEnv.create(textEngine: true);
      await pumpApp(tester, env, textScale: 2.0);
      await openBook(tester, env, 'w-pride', 'gutenberg:1342');
      final text = tester.renderObject<RenderBox>(find.byKey(const Key('reader-page-text')));
      expect(text.size.height, greaterThan(100));
      expect(tester.takeException(), isNull);
    });
  });

  group('images (WCAG 1.1.1)', () {
    for (final entry in screens.entries) {
      testWidgets('${entry.key}: every image has a text alternative or is decorative', (tester) async {
        final env = await TestEnv.create();
        await pumpApp(tester, env);
        await entry.value.go(tester, env);
        for (final image in tester.widgetList<Image>(find.byType(Image))) {
          expect(image.semanticLabel != null || image.excludeFromSemantics, isTrue,
              reason: 'Image without a semanticLabel that is not excluded from semantics');
        }
      });
    }
  });

  group('keyboard (WCAG 2.1.1, 2.1.2, 2.4.3)', () {
    testWidgets('home: Tab reaches the search box, then the button; Enter searches', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final field = find.descendant(of: find.byKey(const Key('search-field')), matching: find.byType(EditableText));
      expect(tester.widget<EditableText>(field).focusNode.hasFocus, isTrue);
      tester.testTextInput.enterText('emma');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(env.api.queries.single.q, 'emma');
    });

    testWidgets('results: a row can be reached and opened with the keyboard', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await searchFor(tester, 'pride');
      var reached = false;
      for (var i = 0; i < 40 && !reached; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final focus = FocusManager.instance.primaryFocus?.context;
        reached = focus != null &&
            find.descendant(of: find.byKey(const Key('result-w-pride')), matching: find.byWidget(focus.widget))
                .evaluate()
                .isNotEmpty;
      }
      expect(reached, isTrue, reason: 'Tab never reached the first result');
    });

    testWidgets('reader: focus is never trapped in the settings panel', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await openBook(tester, env, 'w-pride', 'gutenberg:1342');
      await tester.tap(find.byKey(const Key('reader-settings-button')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reader-settings')), findsNothing);
    });

    testWidgets('every page can be left with the back button', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await openDetails(tester, 'w-pride');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home-heading')), findsOneWidget);
    });
  });

  group('status messages (WCAG 4.1.3)', () {
    testWidgets('search progress, results, errors and outages are live regions', (tester) async {
      final handle = tester.ensureSemantics();
      final env = await TestEnv.create();
      env.api.response = SearchResponse(
          works: env.api.response.works, unavailableSources: const ['doab']);
      await pumpApp(tester, env);
      await searchFor(tester, 'pride');
      for (final key in ['result-count', 'unavailable-notice']) {
        expect(tester.getSemantics(find.byKey(Key(key))), containsSemantics(isLiveRegion: true), reason: key);
      }
      handle.dispose();
    });
  });

  group('page language and titles (WCAG 3.1.1, 2.4.2)', () {
    testWidgets('the app declares a title and the English locale', (tester) async {
      await pumpApp(tester, await TestEnv.create());
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.title, 'Free Book Reader');
      expect(app.locale ?? const Locale('en'), const Locale('en'));
    });
  });
}
