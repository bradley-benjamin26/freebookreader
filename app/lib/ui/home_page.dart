import 'package:flutter/material.dart';

import '../models/models.dart';
import '../util/format.dart';
import 'about_page.dart';
import 'common.dart';
import 'results_page.dart';
import 'search_bar.dart';

const exampleBooks = [
  (title: 'Pride and Prejudice', gutenberg: 1342),
  (title: 'Frankenstein', gutenberg: 84),
  (title: 'Moby Dick', gutenberg: 2701),
  (title: 'The Odyssey', gutenberg: 1727),
];

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  void _search(BuildContext context, SearchField field, String text) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => ResultsPage(initialText: text, initialField: field)));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ScrollColumn(
              padding: const EdgeInsets.all(16),
              children: [
                const SizedBox(height: 8),
                Heading('Free Book Reader',
                    key: const Key('home-heading'), level: 1,
                    style: text.headlineMedium,
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                BookSearchBar(onSearch: (field, text) => _search(context, field, text)),
                const SizedBox(height: 8),
                Text(
                  'Find books that are out of copyright, openly licensed or free to borrow, plus free audiobooks.',
                  key: const Key('home-intro'),
                  style: text.bodyLarge,
                ),
                Text("Some open in this app; others open on the library's own website.", style: text.bodyMedium),
                Text('Sources: Project Gutenberg, LibriVox, DOAB, Open Library and HathiTrust.',
                    style: text.bodySmall),
                const SizedBox(height: 24),
                Heading('Try one of these', style: text.titleMedium),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  key: const Key('example-books'),
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final example in exampleBooks)
                        // One button named by the title (an ActionChip was announced as a checkbox on the web).
                        Semantics(
                          key: Key('example-${example.gutenberg}'),
                          button: true,
                          focusable: true,
                          label: example.title,
                          onTap: () => _search(context, SearchField.title, example.title),
                          excludeSemantics: true,
                          child: InkWell(
                            onTap: () => _search(context, SearchField.title, example.title),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: SizedBox(
                                width: 96,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Cover(
                                        title: example.title,
                                        url: 'https://www.gutenberg.org/cache/epub/${example.gutenberg}'
                                            '/pg${example.gutenberg}.cover.medium.jpg',
                                        width: 96),
                                    const SizedBox(height: 4),
                                    Text(example.title,
                                        style: text.bodyMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Heading('Where the books come from', style: text.titleMedium),
                Wrap(
                  children: [
                    for (final id in sourceIds)
                      TextButton(
                        key: Key('about-link-$id'),
                        onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(builder: (_) => AboutPage(sourceId: id))),
                        child: Text(sourceName(id)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
