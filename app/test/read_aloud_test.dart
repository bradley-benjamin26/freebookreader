// Read aloud (text-to-speech): the controls on the reading screen, against a fake engine that can read aloud
// (group "controls"), and our own renderer reading, highlighting and turning pages, against a fake speech
// service (group "text engine").
//
// NOT covered: flutter_readium's TTS (web, and phones once set up) and the device's voices. They are checked by
// hand with checks 5 and 9 of decision_reader.md.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:free_book_reader/models/models.dart';
import 'package:free_book_reader/reader/pagination.dart';
import 'package:free_book_reader/reader/read_aloud.dart';
import 'package:free_book_reader/reader/reader_settings.dart';
import 'package:free_book_reader/reader/text_engine.dart';
import 'package:free_book_reader/services/speech_engine.dart';

import 'helpers/fakes.dart';
import 'helpers/test_app.dart';

const gutenberg = 'gutenberg:1342';

Future<TestEnv> controlsEnv(WidgetTester tester, {bool readAloud = true}) async {
  final env = await TestEnv.create();
  env.engines.readAloud = readAloud;
  await pumpApp(tester, env);
  await openBook(tester, env, 'w-pride', gutenberg);
  return env;
}

String label(WidgetTester tester, String key) => tester.getSemantics(find.byKey(Key(key))).label;

Future<void> tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

// --- text engine helpers ---------------------------------------------------------------------------------

Future<TestEnv> textEnv(WidgetTester tester, {Map<String, Object> prefs = const {}}) async {
  final env = await TestEnv.create(prefsValues: prefs, textEngine: true);
  await pumpApp(tester, env);
  await openBook(tester, env, 'w-pride', gutenberg);
  return env;
}

/// The text of the page or paragraph as drawn, with the highlight in or not.
Text pageWidget(WidgetTester tester, [String key = 'reader-page-text']) =>
    tester.widget<Text>(find.byKey(Key(key)));

String shown(WidgetTester tester, [String key = 'reader-page-text']) {
  final text = pageWidget(tester, key);
  return text.data ?? text.textSpan!.toPlainText();
}

/// The words drawn highlighted, or null when none are.
String? highlighted(WidgetTester tester, [String key = 'reader-page-text']) {
  final span = pageWidget(tester, key).textSpan;
  if (span == null) return null;
  String? found;
  span.visitChildren((s) {
    if (s is TextSpan && s.style?.backgroundColor != null) found = s.text;
    return true;
  });
  return found;
}

/// The engine speaks the whole current text, word by word, and ends it.
Future<void> readChunk(WidgetTester tester, TestEnv env) async {
  final words = RegExp(r'\S+').allMatches(env.speech.text).length;
  for (var i = 0; i < words; i++) {
    env.speech.say(i);
  }
  env.speech.finish();
  await tester.pumpAndSettle();
}

Future<void> chooseScrollView(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('reader-settings-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('view-scroll')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('settings-close')));
  await tester.pumpAndSettle();
}

void main() {
  group('BookText.wordRange', () {
    final book = BookText(['Once upon,\nwhile I', 'Next  one']);

    test('is where a word is in the text of the words around it', () {
      final text = book.text(0, 6, '\n\n');
      for (var i = 0; i < 6; i++) {
        final (start, end) = book.wordRange(0, i, '\n\n');
        expect(text.substring(start, end), book.words[i].replaceFirst('\n', ''), reason: 'word $i');
      }
    });

    test('counts from the first word shown, which loses the line break before it', () {
      final text = book.text(2, 6, '\n');
      final (start, end) = book.wordRange(2, 2, '\n');
      expect(text.substring(start, end), 'while');
      final (a, b) = book.wordRange(2, 4, '\n');
      expect(text.substring(a, b), 'Next');
    });
  });

  group('speech helpers', () {
    test('a voice is matched by language, whatever the separator or case', () {
      expect(matchVoiceLanguage('en', ['fr-FR', 'en-US', 'en-GB']), 'en-US');
      expect(matchVoiceLanguage('fr', ['en_US', 'fr_CA']), 'fr_CA');
      expect(matchVoiceLanguage('es', ['es']), 'es');
      expect(matchVoiceLanguage('EN', ['en-us']), 'en-us');
      expect(matchVoiceLanguage('de', ['en-US', 'deu-DEU']), isNull); // not a prefix match on letters
    });

    test('speed 1 is flutter_tts 0.5 on a phone and 1 in a browser', () {
      expect(ttsRate(1.0, web: false), 0.5);
      expect(ttsRate(2.0, web: false), 1.0);
      expect(ttsRate(0.5, web: false), 0.25);
      expect(ttsRate(1.5, web: true), 1.5);
    });
  });

  group('controls', () {
    testWidgets('are there when the engine can read aloud, and not when it cannot', (tester) async {
      await controlsEnv(tester);
      expect(find.byKey(const Key('read-aloud-toggle')), findsOneWidget);
      expect(find.byKey(const Key('read-aloud-speed')), findsOneWidget);
    });

    testWidgets('are not there when the engine cannot read aloud', (tester) async {
      await controlsEnv(tester, readAloud: false);
      expect(find.byKey(const Key('read-aloud-toggle')), findsNothing);
    });

    testWidgets('are not there while the book loads', (tester) async {
      final env = await TestEnv.create();
      env.engines
        ..readAloud = true
        ..never = true;
      await pumpApp(tester, env);
      await searchFor(tester, 'pride');
      await tester.tap(find.byKey(const Key('result-w-pride')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('open-$gutenberg')));
      await tester.tap(find.byKey(const Key('open-$gutenberg')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('read-aloud-toggle')), findsNothing);
    });

    testWidgets("start reads in the book's language, and the button says it can pause", (tester) async {
      final env = await controlsEnv(tester);
      final handle = tester.ensureSemantics();
      expect(label(tester, 'read-aloud-toggle'), 'Read aloud');
      await tap(tester, 'read-aloud-toggle');
      expect(env.engines.last.readAloud!.calls, ['start']);
      expect(env.engines.last.readAloud!.language, 'en');
      expect(label(tester, 'read-aloud-toggle'), 'Pause reading aloud');
      handle.dispose();
    });

    testWidgets('pause and resume', (tester) async {
      final env = await controlsEnv(tester);
      final handle = tester.ensureSemantics();
      await tap(tester, 'read-aloud-toggle');
      await tap(tester, 'read-aloud-toggle');
      expect(label(tester, 'read-aloud-toggle'), 'Resume reading aloud');
      await tap(tester, 'read-aloud-toggle');
      expect(env.engines.last.readAloud!.calls, ['start', 'pause', 'resume']);
      expect(label(tester, 'read-aloud-toggle'), 'Pause reading aloud');
      handle.dispose();
    });

    testWidgets('stop is offered only while reading or paused, and starts over', (tester) async {
      final env = await controlsEnv(tester);
      expect(find.byKey(const Key('read-aloud-stop')), findsNothing);
      await tap(tester, 'read-aloud-toggle');
      expect(find.byKey(const Key('read-aloud-stop')), findsOneWidget);
      await tap(tester, 'read-aloud-stop');
      expect(env.engines.last.readAloud!.calls, ['start', 'stop']);
      expect(find.byKey(const Key('read-aloud-stop')), findsNothing);
      expect(find.byKey(const Key('read-aloud-toggle')), findsOneWidget);
    });

    testWidgets('reading that ends by itself puts the button back to "Read aloud"', (tester) async {
      final env = await controlsEnv(tester);
      final handle = tester.ensureSemantics();
      await tap(tester, 'read-aloud-toggle');
      env.engines.last.readAloud!.emit(const ReadAloudState());
      await tester.pumpAndSettle();
      expect(label(tester, 'read-aloud-toggle'), 'Read aloud');
      handle.dispose();
    });

    testWidgets('speed goes up and down through the choices and stops at the ends', (tester) async {
      final env = await controlsEnv(tester);
      expect(find.text('Speed 1×'), findsOneWidget);
      await tap(tester, 'read-aloud-faster');
      expect(find.text('Speed 1.25×'), findsOneWidget);
      await tap(tester, 'read-aloud-faster');
      await tap(tester, 'read-aloud-faster');
      expect(find.text('Speed 2×'), findsOneWidget);
      expect(tester.widget<IconButton>(find.byKey(const Key('read-aloud-faster'))).onPressed, isNull);
      await tap(tester, 'read-aloud-slower');
      expect(find.text('Speed 1.5×'), findsOneWidget);
      for (var i = 0; i < 4; i++) {
        await tap(tester, 'read-aloud-slower');
      }
      expect(find.text('Speed 0.5×'), findsOneWidget);
      expect(tester.widget<IconButton>(find.byKey(const Key('read-aloud-slower'))).onPressed, isNull);
      expect(env.engines.last.readAloud!.calls.first, 'rate 1.25');
    });

    testWidgets('an error is shown and announced', (tester) async {
      final env = await controlsEnv(tester);
      env.engines.last.readAloud!.failNext = 'This device has no voice for English.';
      await tap(tester, 'read-aloud-toggle');
      final handle = tester.ensureSemantics();
      expect(find.text('This device has no voice for English.'), findsOneWidget);
      expect(
          tester.getSemantics(find.byKey(const Key('read-aloud-error'))),
          containsSemantics(label: 'This device has no voice for English.', isLiveRegion: true));
      expect(label(tester, 'read-aloud-toggle'), 'Read aloud');
      handle.dispose();
    });

    testWidgets('starting it pauses the recording, and playing the recording pauses it', (tester) async {
      final env = await controlsEnv(tester);
      await tap(tester, 'play-pause');
      expect(env.audio.playing, isTrue);
      await tap(tester, 'read-aloud-toggle');
      expect(env.audio.playing, isFalse);
      expect(env.engines.last.readAloud!.state.value.status, ReadAloudStatus.reading);
      await tap(tester, 'play-pause');
      expect(env.audio.playing, isTrue);
      expect(env.engines.last.readAloud!.state.value.status, ReadAloudStatus.paused);
    });

    testWidgets('reading aloud while the recording is stopped leaves it alone', (tester) async {
      final env = await controlsEnv(tester);
      await tap(tester, 'read-aloud-toggle');
      expect(env.audio.calls, isNot(contains('pause')));
    });

    testWidgets('meet the tap target and label guidelines, also at 320 px and large text', (tester) async {
      final env = await TestEnv.create();
      env.engines.readAloud = true;
      await pumpApp(tester, env, size: smallPhone, textScale: 2.0);
      await openBook(tester, env, 'w-pride', gutenberg);
      await tap(tester, 'read-aloud-toggle');
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      expect(tester.takeException(), isNull);
    });
  });

  group('text engine', () {
    test('reads in English when the language of the book is not known', () async {
      final speech = FakeSpeechEngine();
      final engine = TextReaderEngine(FakeContentLoader(), speech: speech);
      await engine.open(const ReadingOptions(mode: ReadingMode.inApp, kind: 'html', url: 'https://x.org/b'),
          settings: const ReaderSettings());
      await engine.readAloud!.start();
      expect(speech.spoken.single.language, 'en');
      expect(engine.readAloud!.state.value.status, ReadAloudStatus.reading);
      await engine.dispose();
      expect(speech.speaking, isFalse);
    });

    // Review 2026-10-11-main, #18: a Stop or a closed book while the voices are looked up wins.
    test('stop while the voices are looked up means nothing is spoken', () async {
      final speech = FakeSpeechEngine()..holdVoices = Completer();
      final engine = TextReaderEngine(FakeContentLoader(), speech: speech);
      await engine.open(const ReadingOptions(mode: ReadingMode.inApp, kind: 'html', url: 'https://x.org/b'),
          settings: const ReaderSettings());
      final starting = engine.readAloud!.start();
      await engine.readAloud!.stop();
      speech.holdVoices!.complete();
      await starting;
      expect(speech.spoken, isEmpty);
      expect(engine.readAloud!.state.value.status, ReadAloudStatus.stopped);
      await engine.dispose();
    });

    test('closing the book while the voices are looked up means nothing is spoken', () async {
      final speech = FakeSpeechEngine()..holdVoices = Completer();
      final engine = TextReaderEngine(FakeContentLoader(), speech: speech);
      await engine.open(const ReadingOptions(mode: ReadingMode.inApp, kind: 'html', url: 'https://x.org/b'),
          settings: const ReaderSettings());
      final starting = engine.readAloud!.start();
      await engine.dispose();
      speech.holdVoices!.complete();
      await starting;
      expect(speech.spoken, isEmpty);
    });

    testWidgets('has no read aloud without a speech service', (tester) async {
      final env = await TestEnv.create(textEngine: true, speech: false);
      await pumpApp(tester, env);
      await openBook(tester, env, 'w-pride', gutenberg);
      expect(find.byKey(const Key('read-aloud-toggle')), findsNothing);
    });

    testWidgets('speaks from the first word on the page, in the language of the book', (tester) async {
      final env = await textEnv(tester);
      await tap(tester, 'read-aloud-toggle');
      expect(env.speech.spoken, hasLength(1));
      expect(env.speech.text, startsWith('Paragraph 0. It is a truth'));
      expect(env.speech.spoken.single.language, 'en');
      expect(env.speech.spoken.single.rate, 1.0);
    });

    testWidgets('a language without a voice is said, and nothing is spoken', (tester) async {
      final env = await textEnv(tester);
      env.speech.languages = {'fr'};
      await tap(tester, 'read-aloud-toggle');
      expect(env.speech.spoken, isEmpty);
      expect(find.byKey(const Key('read-aloud-error')), findsOneWidget);
      expect(find.textContaining('no voice'), findsOneWidget);
      expect(find.textContaining('English'), findsOneWidget);
      expect(highlighted(tester), isNull);
    });

    testWidgets('highlights the word being spoken, and moves with the speech', (tester) async {
      final env = await textEnv(tester);
      await tap(tester, 'read-aloud-toggle');
      expect(highlighted(tester), isNull); // nothing spoken yet
      env.speech.say(0);
      await tester.pump();
      expect(highlighted(tester), 'Paragraph');
      env.speech.say(1);
      await tester.pump();
      expect(highlighted(tester), '0.');
      env.speech.say(5);
      await tester.pump();
      expect(highlighted(tester), 'truth');
    });

    testWidgets('the text on the page is unchanged by the highlight', (tester) async {
      final env = await textEnv(tester);
      final before = shown(tester);
      await tap(tester, 'read-aloud-toggle');
      env.speech.say(7);
      await tester.pump();
      expect(shown(tester), before);
    });

    testWidgets('the highlight is high contrast: the page colours swapped', (tester) async {
      final env = await textEnv(tester, prefs: {'reader_settings': '{"theme":"dark"}'});
      await tap(tester, 'read-aloud-toggle');
      env.speech.say(2);
      await tester.pump();
      final span = pageWidget(tester).textSpan!;
      TextStyle? style;
      span.visitChildren((s) {
        if (s is TextSpan && s.style?.backgroundColor != null) style = s.style;
        return true;
      });
      final page = pageWidget(tester).style!;
      expect(style!.backgroundColor, page.color);
      expect(style!.color, isNot(page.color));
    });

    testWidgets('goes on with the words after the last one it was given', (tester) async {
      final env = await textEnv(tester);
      await tap(tester, 'read-aloud-toggle');
      final first = env.speech.text;
      await readChunk(tester, env);
      expect(env.speech.spoken, hasLength(2));
      final second = env.speech.text;
      expect(first, isNot(second));
      // The chunks are in the book's order with nothing missing or repeated.
      final text = shown(tester).replaceAll('\n', ' ');
      expect(text, startsWith('$first $second'));
    });

    testWidgets('turns the page when the speech reaches the next one', (tester) async {
      final env = await textEnv(tester);
      await tap(tester, 'read-aloud-toggle');
      expect(pageNumber(tester), 1);
      for (var i = 0; i < 40 && pageNumber(tester) == 1; i++) {
        await readChunk(tester, env);
      }
      expect(pageNumber(tester), 2);
      expect(env.speech.speaking, isTrue);
      env.speech.say(0);
      await tester.pump();
      expect(highlighted(tester), env.speech.text.split(' ').first);
    });

    testWidgets('a page the reader turns to is read from its start', (tester) async {
      final env = await textEnv(tester);
      await tap(tester, 'read-aloud-toggle');
      env.speech.say(3);
      await nextPage(tester);
      expect(pageNumber(tester), 2);
      expect(env.speech.spoken, hasLength(2));
      final onPage = shown(tester);
      final spoken = env.speech.text;
      expect(onPage, startsWith(spoken.substring(0, spoken.length < 8 ? spoken.length : 8)));
      expect(env.speech.stops, greaterThan(0));
    });

    testWidgets('reading stops at the end of the book', (tester) async {
      final env = await TestEnv.create(textEngine: true);
      env.loader.content = longText(paragraphs: 1);
      await pumpApp(tester, env);
      await openBook(tester, env, 'w-pride', gutenberg);
      await tap(tester, 'read-aloud-toggle');
      for (var i = 0; i < 10 && env.speech.speaking; i++) {
        await readChunk(tester, env);
      }
      expect(env.speech.speaking, isFalse);
      final handle = tester.ensureSemantics();
      expect(label(tester, 'read-aloud-toggle'), 'Read aloud');
      expect(highlighted(tester), isNull);
      handle.dispose();
    });

    testWidgets('pause stops the speech and keeps the highlight; resume goes on from that word', (tester) async {
      final env = await textEnv(tester);
      await tap(tester, 'read-aloud-toggle');
      env.speech.say(5);
      await tester.pump();
      await tap(tester, 'read-aloud-toggle'); // pause
      expect(env.speech.speaking, isFalse);
      expect(highlighted(tester), 'truth');
      await tap(tester, 'read-aloud-toggle'); // resume
      expect(env.speech.spoken, hasLength(2));
      expect(env.speech.text, startsWith('truth universally'));
    });

    testWidgets('stop clears the highlight, and the next start begins at the page again', (tester) async {
      final env = await textEnv(tester);
      await tap(tester, 'read-aloud-toggle');
      env.speech.say(5);
      await tester.pump();
      await tap(tester, 'read-aloud-stop');
      expect(env.speech.speaking, isFalse);
      expect(highlighted(tester), isNull);
      await tap(tester, 'read-aloud-toggle');
      expect(env.speech.text, startsWith('Paragraph 0.'));
    });

    testWidgets('a new speed is used from the word being spoken', (tester) async {
      final env = await textEnv(tester);
      await tap(tester, 'read-aloud-toggle');
      env.speech.say(5);
      await tester.pump();
      await tap(tester, 'read-aloud-faster');
      expect(env.speech.spoken, hasLength(2));
      expect(env.speech.spoken.last.rate, 1.25);
      expect(env.speech.text, startsWith('truth universally'));
      await readChunk(tester, env);
      expect(env.speech.spoken.last.rate, 1.25); // and for the chunks after it
    });

    testWidgets('a new speed while stopped is kept for the next start', (tester) async {
      final env = await textEnv(tester);
      await tap(tester, 'read-aloud-faster');
      expect(env.speech.spoken, isEmpty);
      await tap(tester, 'read-aloud-toggle');
      expect(env.speech.spoken.single.rate, 1.25);
    });

    testWidgets('a speech failure stops reading and says so', (tester) async {
      final env = await textEnv(tester);
      env.speech.failNext = const SpeechException('the speech service stopped');
      await tap(tester, 'read-aloud-toggle');
      expect(find.byKey(const Key('read-aloud-error')), findsOneWidget);
      final handle = tester.ensureSemantics();
      expect(label(tester, 'read-aloud-toggle'), 'Read aloud');
      handle.dispose();
      // And the reader can try again.
      await tap(tester, 'read-aloud-toggle');
      expect(find.byKey(const Key('read-aloud-error')), findsNothing);
      expect(env.speech.speaking, isTrue);
    });

    testWidgets('leaving the book stops the speech', (tester) async {
      final env = await textEnv(tester);
      await tap(tester, 'read-aloud-toggle');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(env.speech.speaking, isFalse);
    });

    testWidgets('a font size change while reading keeps the place', (tester) async {
      final env = await textEnv(tester);
      await tap(tester, 'read-aloud-toggle');
      env.speech.say(5);
      await tester.pump();
      await tester.tap(find.byKey(const Key('reader-settings-button')));
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const Key('font-increase')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const Key('settings-close')));
      await tester.pumpAndSettle();
      expect(env.speech.speaking, isTrue);
      expect(highlighted(tester), 'truth');
    });

    group('scroll view', () {
      testWidgets('highlights the word in its paragraph', (tester) async {
        final env = await textEnv(tester);
        await chooseScrollView(tester);
        await tap(tester, 'read-aloud-toggle');
        expect(env.speech.text, startsWith('Paragraph 0.'));
        env.speech.say(5);
        await tester.pump();
        expect(highlighted(tester, 'reader-paragraph-0'), 'truth');
        expect(shown(tester, 'reader-paragraph-0'), startsWith('Paragraph 0. It is a truth'));
      });

      testWidgets('goes on into the next paragraph and scrolls it into view', (tester) async {
        final env = await textEnv(tester);
        await chooseScrollView(tester);
        await tap(tester, 'read-aloud-toggle');
        for (var i = 0; i < 40; i++) {
          await readChunk(tester, env);
        }
        env.speech.say(0);
        await tester.pumpAndSettle();
        final word = env.speech.text.split(' ').first;
        final spoken = find.byWidgetPredicate((w) => w is Text && w.textSpan != null && _has(w, word));
        expect(spoken, findsWidgets);
        final box = tester.getRect(spoken.first);
        expect(box.top, greaterThanOrEqualTo(0));
        expect(box.bottom, lessThanOrEqualTo(800));
      });

      // Review 2026-10-11-main #20: the place in the scroll view is the line at the top, not its paragraph's start.
      testWidgets('speaks from the line at the top, not from the start of the book', (tester) async {
        final env = await textEnv(tester);
        await chooseScrollView(tester);
        await tester.drag(find.byKey(const Key('reader-scroll')), const Offset(0, -3000));
        await tester.pumpAndSettle();
        await tap(tester, 'read-aloud-toggle');
        expect(env.speech.text, isNot(startsWith('Paragraph 0.')));
        // The words spoken first are in the first paragraph that reaches below the top of the view.
        final top = tester.getTopLeft(find.byKey(const Key('reader-scroll'))).dy;
        final shownParagraphs = tester
            .widgetList<Text>(find.byWidgetPredicate((w) =>
                w is Text && w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('reader-paragraph-')))
            .toList()
          ..sort((a, b) => tester.getRect(find.byWidget(a)).top.compareTo(tester.getRect(find.byWidget(b)).top));
        final paragraph = shownParagraphs.firstWhere((t) => tester.getRect(find.byWidget(t)).bottom > top);
        final opening = env.speech.text.split(' ').take(4).join(' ');
        expect(paragraph.data ?? paragraph.textSpan!.toPlainText(), contains(opening));
      });
    });
  });
}

bool _has(Text text, String word) {
  var found = false;
  text.textSpan!.visitChildren((s) {
    if (s is TextSpan && s.style?.backgroundColor != null && s.text == word) found = true;
    return true;
  });
  return found;
}
