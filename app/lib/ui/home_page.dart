import 'package:flutter/material.dart';

import '../models/models.dart';
import '../util/format.dart';
import 'about_page.dart';
import 'common.dart';
import 'results_page.dart';
import 'search_bar.dart';

const exampleSearches = ['Pride and Prejudice', 'Frankenstein', 'Moby Dick', 'The Odyssey'];

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
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ScrollColumn(
              padding: const EdgeInsets.all(16),
              children: [
                const SizedBox(height: 8),
                Heading('Free Book Reader',
                    key: const Key('home-heading'),
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
                Wrap(
                  key: const Key('example-books'),
                  spacing: 8,
                  children: [
                    for (final example in exampleSearches)
                      ActionChip(
                        label: Text(example),
                        onPressed: () => _search(context, SearchField.title, example),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                Heading('Where the books come from', style: text.titleMedium),
                for (final id in sourceIds)
                  ListTile(
                    key: Key('about-link-$id'),
                    title: Text('About ${sourceName(id)}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => AboutPage(sourceId: id))),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
