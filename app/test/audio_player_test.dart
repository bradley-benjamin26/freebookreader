// Listening: audiobooks play in the app, and while reading a book that has a
// LibriVox recording the reader and the player are both on screen.
//
// NOT covered yet: syncing the text position to the audio position. The spec
// allows falling back to "viewer and player both display" if syncing is too
// hard; decide before writing tests for it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:free_book_reader/models/models.dart';

import 'helpers/fixtures.dart';
import 'helpers/test_app.dart';

const chapter1 = 'https://archive.org/download/p/01.mp3';
const chapter2 = 'https://archive.org/download/p/02.mp3';
const chapter3 = 'https://archive.org/download/p/03.mp3';

SearchResponse modified(void Function(Map<String, dynamic> pride) change) {
  final json = loadJson('search_response.json') as Map<String, dynamic>;
  change((json['works'] as List).first as Map<String, dynamic>);
  return SearchResponse.fromJson(json);
}

Future<void> openAudio(WidgetTester tester, TestEnv env) =>
    openBook(tester, env, 'w-pride', 'librivox:253');

String playLabel(WidgetTester tester) =>
    tester.getSemantics(find.byKey(const Key('play-pause'))).label;

void main() {
  group('audiobook page', () {
    testWidgets('shows the title, narrators and length', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await openAudio(tester, env);
      expect(tester.getSemantics(find.byKey(const Key('audio-title'))),
          containsSemantics(isHeader: true, label: 'Pride and Prejudice'));
      expect(find.textContaining('Chris Goringe'), findsOneWidget);
      expect(find.textContaining('13 hr 6 min'), findsWidgets);
    });

    testWidgets('has the player but no text viewer', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await openAudio(tester, env);
      expect(find.byKey(const Key('audio-player')), findsOneWidget);
      expect(find.byKey(const Key('reader-page-text')), findsNothing);
    });

    testWidgets('lists the chapters with their lengths', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await openAudio(tester, env);
      for (var i = 0; i < 3; i++) {
        expect(find.byKey(Key('chapter-$i')), findsOneWidget);
      }
      expect(find.descendant(of: find.byKey(const Key('chapter-0')), matching: find.text('Chapters 1-3')),
          findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('chapter-0')), matching: find.text('18 min')),
          findsOneWidget);
    });
  });

  group('controls', () {
    testWidgets('play starts the first chapter and the button becomes Pause', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await openAudio(tester, env);
      expect(playLabel(tester), 'Play');
      await tester.tap(find.byKey(const Key('play-pause')));
      await tester.pumpAndSettle();
      expect(env.audio.calls.last, 'play $chapter1');
      expect(playLabel(tester), 'Pause');
    });

    testWidgets('pause stops playback and the button becomes Play again', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await openAudio(tester, env);
      await tester.tap(find.byKey(const Key('play-pause')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('play-pause')));
      await tester.pumpAndSettle();
      expect(env.audio.calls.last, 'pause');
      expect(playLabel(tester), 'Play');
    });

    testWidgets('choosing a chapter plays it', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await openAudio(tester, env);
      await tester.tap(find.byKey(const Key('chapter-1')));
      await tester.pumpAndSettle();
      expect(env.audio.calls.last, 'play $chapter2');
      expect(playLabel(tester), 'Pause');
    });

    testWidgets('the current chapter is marked as selected', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await openAudio(tester, env);
      await tester.tap(find.byKey(const Key('chapter-2')));
      await tester.pumpAndSettle();
      expect(tester.getSemantics(find.byKey(const Key('chapter-2'))), containsSemantics(isSelected: true));
      expect(tester.getSemantics(find.byKey(const Key('chapter-0'))),
          isNot(containsSemantics(isSelected: true)));
    });

    testWidgets('chapters have names that include the title', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await openAudio(tester, env);
      final chapter = tester.getSemantics(find.byKey(const Key('chapter-1')));
      expect(chapter, containsSemantics(isButton: true));
      expect(chapter.label, contains('Chapters 4-7'));
    });

    testWidgets('skip back and forward move by 30 seconds', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await openAudio(tester, env);
      await tester.tap(find.byKey(const Key('play-pause')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('skip-forward')));
      await tester.pumpAndSettle();
      expect(env.audio.calls.last, 'seek 30');
      expect(tester.getSemantics(find.byKey(const Key('skip-forward'))),
          containsSemantics(isButton: true, label: 'Skip forward 30 seconds'));
      expect(tester.getSemantics(find.byKey(const Key('skip-back'))),
          containsSemantics(isButton: true, label: 'Skip back 30 seconds'));
    });

    testWidgets('there is a labeled position slider', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await openAudio(tester, env);
      expect(tester.getSemantics(find.byKey(const Key('position-slider'))),
          containsSemantics(isSlider: true, label: 'Playback position'));
    });

    testWidgets('leaving the page stops playback', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await openAudio(tester, env);
      await tester.tap(find.byKey(const Key('play-pause')));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(env.audio.playing, isFalse);
    });
  });

  group('listen while reading', () {
    testWidgets('the reader shows the player too when a recording exists', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await openBook(tester, env, 'w-pride', 'gutenberg:1342');
      expect(find.byKey(const Key('reader-page-text')), findsOneWidget);
      expect(find.byKey(const Key('audio-player')), findsOneWidget);
    });

    testWidgets('the player in the reader plays the recording', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await openBook(tester, env, 'w-pride', 'gutenberg:1342');
      await tester.tap(find.byKey(const Key('play-pause')));
      await tester.pumpAndSettle();
      expect(env.audio.calls.last, 'play $chapter1');
      expect(find.byKey(const Key('reader-page-text')), findsOneWidget);
    });

    testWidgets('the recording can be paused while turning pages', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await openBook(tester, env, 'w-pride', 'gutenberg:1342');
      await tester.tap(find.byKey(const Key('play-pause')));
      await tester.pumpAndSettle();
      await nextPage(tester);
      expect(pageNumber(tester), 2);
      expect(env.audio.playing, isTrue);
    });

    testWidgets('no player when the book has no recording', (tester) async {
      final env = await TestEnv.create(response: modified((pride) {
        (pride['books'] as List).removeWhere((b) => b['source'] == 'librivox');
      }));
      await pumpApp(tester, env);
      await openBook(tester, env, 'w-pride', 'gutenberg:1342');
      expect(find.byKey(const Key('reader-page-text')), findsOneWidget);
      expect(find.byKey(const Key('audio-player')), findsNothing);
    });

    testWidgets('no player when the recording is in a different language', (tester) async {
      final env = await TestEnv.create(response: modified((pride) {
        for (final b in pride['books'] as List) {
          if (b['source'] == 'librivox') b['language'] = 'fr';
        }
      }));
      await pumpApp(tester, env);
      await openBook(tester, env, 'w-pride', 'gutenberg:1342');
      expect(find.byKey(const Key('audio-player')), findsNothing);
    });

    testWidgets('a pdf has no player', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await openBook(tester, env, 'w-kinder', 'doab:20.500.12854/95506');
      expect(find.byKey(const Key('audio-player')), findsNothing);
    });

    testWidgets('the player does not hide the text on a small phone', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env, size: smallPhone);
      await openBook(tester, env, 'w-pride', 'gutenberg:1342');
      final text = tester.getRect(find.byKey(const Key('reader-page-text')));
      final player = tester.getRect(find.byKey(const Key('audio-player')));
      expect(text.overlaps(player), isFalse);
      expect(text.height, greaterThan(200));
    });
  });
}
