import 'package:flutter/material.dart';

import '../app.dart';
import '../models/models.dart';
import '../util/format.dart';
import 'audio_player.dart';
import 'common.dart';

/// An audiobook: title, narrators, the player and the chapter list.
class AudioPage extends StatefulWidget {
  const AudioPage({super.key, required this.work, required this.book});

  final Work work;
  final Book book;

  @override
  State<AudioPage> createState() => _AudioPageState();
}

class _AudioPageState extends State<AudioPage> {
  AudioController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller ??= AudioController(Services.of(context).audio, widget.book);
  }

  @override
  void dispose() {
    _controller!.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final controller = _controller!;
    final text = Theme.of(context).textTheme;
    final narrators = joinNames(book.narrators);
    final length = formatDuration(book.audioSeconds);
    return Scaffold(
      key: const Key('audio-page'),
      appBar: AppBar(title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ScrollColumn(
            padding: const EdgeInsets.all(16),
            children: [
              Heading(book.title, key: const Key('audio-title'), style: text.headlineSmall),
              Text(formatAuthors(book.authors), style: text.titleMedium),
              if (narrators != null) Text('Read by $narrators', style: text.bodyMedium),
              if (length != null) Text('Length: $length', style: text.bodyMedium),
              const SizedBox(height: 16),
              AudioPlayerPanel(key: const Key('audio-player'), controller: controller),
              const SizedBox(height: 16),
              Heading('Chapters', style: text.titleLarge),
              ListenableBuilder(
                listenable: controller,
                builder: (context, _) => Column(
                  children: [
                    for (final (i, chapter) in book.chapters.indexed)
                      ListTile(
                        key: Key('chapter-$i'),
                        selected: controller.chapter == i,
                        title: Text(chapter.title),
                        trailing: Text(formatDuration(chapter.durationSeconds) ?? ''),
                        onTap: () => controller.playChapter(i),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
