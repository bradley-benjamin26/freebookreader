// Listening: audiobooks play in the app, and while reading a book that has a
// LibriVox recording the reader and the player are both on screen.
//
// NOT covered yet: syncing the text position to the audio position. The spec
// allows falling back to "viewer and player both display" if syncing is too
// hard; decide before writing tests for it.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:free_book_reader/models/models.dart';
import 'package:free_book_reader/services/audio_engine.dart';
import 'package:free_book_reader/ui/audio_player.dart';

import 'helpers/fakes.dart';
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
      expect(find.byKey(const Key('fake-reader-view')), findsNothing);
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

  group('when playback fails or ends', () {
    // Review 2026-10-11, #12: the button stayed on "Pause" with no message, and chapters never moved on.
    testWidgets('a recording that cannot be played shows a message and the button reads Play', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await openAudio(tester, env);
      env.audio.failNext = true;
      await tester.tap(find.byKey(const Key('play-pause')));
      await tester.pumpAndSettle();
      expect(playLabel(tester), 'Play');
      final error = find.byKey(const Key('audio-error'));
      expect(error, findsOneWidget);
      expect(tester.getSemantics(error), containsSemantics(isLiveRegion: true));
      expect(find.descendant(of: error, matching: find.textContaining('could not be played')), findsOneWidget);
    });

    testWidgets('Try again plays it, and the message goes away', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await openAudio(tester, env);
      env.audio.failNext = true;
      await tester.tap(find.byKey(const Key('play-pause')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('audio-retry')));
      await tester.pumpAndSettle();
      expect(env.audio.calls.where((c) => c == 'play $chapter1'), hasLength(2));
      expect(find.byKey(const Key('audio-error')), findsNothing);
      expect(playLabel(tester), 'Pause');
    });

    testWidgets('a chapter that fails shows the same message', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await openAudio(tester, env);
      env.audio.failNext = true;
      await tester.tap(find.byKey(const Key('chapter-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('audio-error')), findsOneWidget);
      expect(playLabel(tester), 'Play');
    });

    testWidgets('the compact player under the reader shows the message too', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await openBook(tester, env, 'w-pride', 'gutenberg:1342');
      env.audio.failNext = true;
      await tester.tap(find.byKey(const Key('play-pause')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('audio-error')), findsOneWidget);
      expect(find.byKey(const Key('fake-reader-view')), findsOneWidget);
    });

    testWidgets('when a chapter ends, the next one starts', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await openAudio(tester, env);
      await tester.tap(find.byKey(const Key('play-pause')));
      await tester.pumpAndSettle();
      env.audio.emitStatus(playing: false, completed: true);
      await tester.pumpAndSettle();
      expect(env.audio.calls.last, 'play $chapter2');
      expect(playLabel(tester), 'Pause');
      expect(tester.getSemantics(find.byKey(const Key('chapter-1'))), containsSemantics(isSelected: true));
    });

    testWidgets('when the last chapter ends, the button reads Play again', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await openAudio(tester, env);
      await tester.tap(find.byKey(const Key('chapter-2')));
      await tester.pumpAndSettle();
      env.audio.emitStatus(playing: false, completed: true);
      await tester.pumpAndSettle();
      expect(env.audio.calls.last, 'play $chapter3');
      expect(playLabel(tester), 'Play');
      expect(find.byKey(const Key('audio-error')), findsNothing);
    });

    // Review 2026-10-11-main, #17: the finished file is still loaded, at its end.
    testWidgets('Play after the last chapter ended starts it again from the beginning', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await openAudio(tester, env);
      await tester.tap(find.byKey(const Key('chapter-2')));
      await tester.pumpAndSettle();
      env.audio.emitStatus(playing: false, completed: true);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('play-pause')));
      await tester.pumpAndSettle();
      expect(env.audio.calls.last, 'play $chapter3');
      expect(env.audio.playedFrom.last, Duration.zero);
    });

    testWidgets('choosing the chapter that is already loaded starts it from the beginning', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await openAudio(tester, env);
      await tester.tap(find.byKey(const Key('play-pause')));
      await tester.pumpAndSettle();
      env.audio.emitPosition(Uri.parse(chapter1), const Duration(minutes: 5));
      await tester.tap(find.byKey(const Key('play-pause')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chapter-0')));
      await tester.pumpAndSettle();
      expect(env.audio.calls.last, 'play $chapter1');
      expect(env.audio.playedFrom.last, Duration.zero);
    });

    testWidgets('Play after Pause goes on from where it stopped', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await openAudio(tester, env);
      await tester.tap(find.byKey(const Key('play-pause')));
      await tester.pumpAndSettle();
      env.audio.emitPosition(Uri.parse(chapter1), const Duration(minutes: 5));
      await tester.tap(find.byKey(const Key('play-pause')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('play-pause')));
      await tester.pumpAndSettle();
      expect(env.audio.playedFrom.last, const Duration(minutes: 5));
    });

    testWidgets('playback stopped from outside (a headset button) shows as Play', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await openAudio(tester, env);
      await tester.tap(find.byKey(const Key('play-pause')));
      await tester.pumpAndSettle();
      env.audio.emitStatus(playing: false);
      await tester.pumpAndSettle();
      expect(playLabel(tester), 'Play');
    });
  });

  group('one engine, several recordings', () {
    // Review 2026-10-11, #18: the player is shared, and a new listener gets its last position at once.
    Book recording(String id) {
      final json = jsonDecode(loadFixtureText('search_response.json')) as Map<String, dynamic>;
      final book = ((json['works'] as List).first['books'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((b) => b['source'] == 'librivox');
      book['source_id'] = id;
      for (final chapter in book['chapters'] as List) {
        chapter['url'] = (chapter['url'] as String).replaceFirst('/p/', '/$id/');
      }
      book['content'] = {'audio/mpeg': 'https://archive.org/download/$id/01.mp3'};
      return Book.fromJson(book);
    }

    test("a new recording does not start at the previous recording's position", () async {
      final engine = FakeAudioEngine();
      final a = AudioController(engine, recording('a'));
      await a.togglePlay();
      engine.emitPosition(Uri.parse('https://archive.org/download/a/01.mp3'), const Duration(minutes: 20));
      await Future<void>.delayed(Duration.zero);
      expect(a.position, const Duration(minutes: 20));
      await a.togglePlay(); // pause
      a.dispose();

      final b = AudioController(engine, recording('b'));
      await Future<void>.delayed(Duration.zero);
      expect(b.position, Duration.zero);
      await b.togglePlay();
      expect(engine.calls.last, 'play https://archive.org/download/b/01.mp3');
      expect(engine.playedFrom.last, isNull);
      b.dispose();
    });

    test('a position of another file is ignored while playing too', () async {
      final engine = FakeAudioEngine();
      final b = AudioController(engine, recording('b'));
      await b.togglePlay();
      engine.emitPosition(Uri.parse('https://archive.org/download/a/01.mp3'), const Duration(minutes: 5));
      engine.emitPosition(Uri.parse('https://archive.org/download/b/01.mp3'), const Duration(seconds: 12));
      await Future<void>.delayed(Duration.zero);
      expect(b.position, const Duration(seconds: 12));
      b.dispose();
    });
  });

  group('listen while reading', () {
    testWidgets('the reader shows the player too when a recording exists', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await openBook(tester, env, 'w-pride', 'gutenberg:1342');
      expect(find.byKey(const Key('fake-reader-view')), findsOneWidget);
      expect(find.byKey(const Key('audio-player')), findsOneWidget);
    });

    testWidgets('the player in the reader plays the recording', (tester) async {
      final env = await TestEnv.create();
      await pumpApp(tester, env);
      await openBook(tester, env, 'w-pride', 'gutenberg:1342');
      await tester.tap(find.byKey(const Key('play-pause')));
      await tester.pumpAndSettle();
      expect(env.audio.calls.last, 'play $chapter1');
      expect(find.byKey(const Key('fake-reader-view')), findsOneWidget);
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
      expect(find.byKey(const Key('fake-reader-view')), findsOneWidget);
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
      final text = tester.getRect(find.byKey(const Key('reader-surface')));
      final player = tester.getRect(find.byKey(const Key('audio-player')));
      expect(text.overlaps(player), isFalse);
      expect(text.height, greaterThan(200));
    });
  });
}
