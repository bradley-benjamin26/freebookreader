// Throwaway spike for decision_reader.md. Not part of app/.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_readium/flutter_readium.dart';

void main() => runApp(const MaterialApp(home: SpikePage()));

class SpikePage extends StatefulWidget {
  const SpikePage({super.key});
  @override
  State<SpikePage> createState() => _SpikePageState();
}

class _SpikePageState extends State<SpikePage> {
  final _readium = FlutterReadium();
  final _url = TextEditingController(
      text: const String.fromEnvironment('BOOK_URL',
          defaultValue: 'http://localhost:8000/publications/gutenberg/1342/manifest.json'));
  Publication? _pub;
  String _log = '';
  String? _savedLocator;
  Locator? _locator;
  double _fontSize = 1.0;
  bool _scroll = false;
  bool _dark = false;
  bool _tts = false;
  final _subs = <StreamSubscription>[];
  Stopwatch? _openWatch;
  Stopwatch? _firstPage;

  void _say(String m) => setState(() => _log = '$m\n$_log');

  @override
  void initState() {
    super.initState();
    _subs.add(_readium.onTextLocatorChanged.listen((l) {
      if (_firstPage != null && _firstPage!.isRunning) {
        _firstPage!.stop();
        _say('first page after ${_firstPage!.elapsedMilliseconds} ms');
      }
      setState(() => _locator = l);
    }));
    _subs.add(_readium.onReaderStatusChanged.listen((s) => _say('status: $s')));
    _subs.add(_readium.onTimebasedPlayerStateChanged
        .listen((s) => _say('tts/audio state: ${s.state}')));
    _subs.add(_readium.onErrorEvent.listen((e) => _say('error: $e')));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  Future<void> _open() async {
    try {
      if (_pub != null) await _readium.closePublication();
      _openWatch = Stopwatch()..start();
      final p = await _readium.openPublication(_url.text);
      _say('opened in ${_openWatch!.elapsedMilliseconds} ms: '
          '${p.metadata.title}');
      _firstPage = Stopwatch()..start();
      setState(() => _pub = p);
    } catch (e) {
      _say('open failed: $e');
    }
  }

  Future<void> _prefs() => _readium.setEPUBPreferences(EPUBPreferences(
        fontSize: _fontSize,
        scroll: _scroll,
        backgroundColor: _dark ? const Color(0xFF121212) : Colors.white,
        textColor: _dark ? const Color(0xFFE6E6E6) : const Color(0xFF111111),
        lineHeight: 1.6,
      ));

  Future<void> _toggleTts() async {
    if (!_tts) {
      await _readium.ttsEnable(TTSPreferences(speed: 1.0));
      await _readium.play(null);
      setState(() => _tts = true);
    } else {
      await _readium.stop();
      setState(() => _tts = false);
    }
  }

  Future<void> _listVoices() async {
    final v = await _readium.ttsGetAvailableVoices();
    _say('${v.length} voices: ${v.take(8).map((e) => '${e.name}/${e.language}').join(', ')}');
  }

  @override
  Widget build(BuildContext context) {
    final progress = _locator?.locations?.totalProgression;
    return Scaffold(
      appBar: AppBar(title: const Text('Reader spike')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(children: [
            Expanded(
                child: TextField(
                    controller: _url,
                    decoration: const InputDecoration(labelText: 'EPUB URL'))),
            FilledButton(onPressed: _open, child: const Text('Open')),
          ]),
        ),
        Wrap(spacing: 4, children: [
          OutlinedButton(
              onPressed: () => _readium.goBackward(), child: const Text('Prev')),
          OutlinedButton(
              onPressed: () => _readium.goForward(), child: const Text('Next')),
          OutlinedButton(
              onPressed: () {
                _fontSize += 0.2;
                _prefs();
              },
              child: const Text('A+')),
          OutlinedButton(
              onPressed: () {
                _fontSize = (_fontSize - 0.2).clamp(0.5, 2.0);
                _prefs();
              },
              child: const Text('A-')),
          OutlinedButton(
              onPressed: () {
                _scroll = !_scroll;
                _prefs();
              },
              child: Text(_scroll ? 'Page view' : 'Scroll view')),
          OutlinedButton(
              onPressed: () {
                _dark = !_dark;
                _prefs();
              },
              child: Text(_dark ? 'Light' : 'Dark')),
          OutlinedButton(
              onPressed: () {
                if (_locator != null) {
                  _savedLocator = jsonEncode(_locator!.toJson());
                  _say('saved position ${(progress ?? 0).toStringAsFixed(3)}');
                }
              },
              child: const Text('Save pos')),
          OutlinedButton(
              onPressed: () async {
                if (_savedLocator == null) return;
                final ok = await _readium
                    .goToLocator(Locator.fromJsonString(_savedLocator!)!);
                _say('restore: $ok');
              },
              child: const Text('Restore pos')),
          OutlinedButton(
              onPressed: _toggleTts,
              child: Text(_tts ? 'Stop TTS' : 'Start TTS')),
          OutlinedButton(
              onPressed: () => _readium.pause(), child: const Text('Pause')),
          OutlinedButton(
              onPressed: () => _readium.resume(), child: const Text('Resume')),
          OutlinedButton(onPressed: _listVoices, child: const Text('Voices')),
        ]),
        Text('progress: ${progress?.toStringAsFixed(3) ?? '-'}'),
        Expanded(
          flex: 3,
          child: _pub == null
              ? const Center(child: Text('Open a book'))
              : ReadiumReaderWidget(publication: _pub!),
        ),
        Expanded(
            child: SingleChildScrollView(
                child: Text(_log, style: const TextStyle(fontSize: 11)))),
      ]),
    );
  }
}
