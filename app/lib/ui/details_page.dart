import 'package:flutter/material.dart';

import '../app.dart';
import '../models/models.dart';
import '../util/format.dart';
import 'common.dart';

const _identifierNames = {
  'isbn': 'ISBN',
  'doi': 'DOI',
  'oclc': 'OCLC',
  'lccn': 'LCCN',
  'gutenberg': 'Project Gutenberg number',
};

/// Everything known about a work, and every way to get at it.
class DetailsPage extends StatelessWidget {
  const DetailsPage({super.key, required this.work});

  final Work work;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      key: const Key('details-page'),
      appBar: AppBar(title: Text(work.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ScrollColumn(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: Cover(
                    key: const Key('details-cover'), title: work.title, url: work.coverUrl, width: 160),
              ),
              const SizedBox(height: 16),
              Heading(work.title, key: const Key('details-title'), style: text.headlineSmall),
              const SizedBox(height: 8),
              _Metadata(key: const Key('details-metadata'), work: work),
              const SizedBox(height: 24),
              Heading('Ways to read or listen', style: text.titleLarge),
              for (final book in work.books) _BookCard(key: Key('book-${book.key}'), work: work, book: book),
            ],
          ),
        ),
      ),
    );
  }
}

class _Metadata extends StatelessWidget {
  const _Metadata({super.key, required this.work});

  final Work work;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget line(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text('$label: $value', style: text.bodyLarge),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        line(work.authors.length > 1 ? 'Authors' : 'Author', formatAuthors(work.authors)),
        line('Language', languageName(work.language)),
        line('Available from', work.sources.map(sourceName).join(', ')),
        for (final entry in work.identifiers.entries)
          if (entry.value.isNotEmpty)
            line(_identifierNames[entry.key] ?? entry.key.toUpperCase(), entry.value.join(', ')),
      ],
    );
  }
}

String _accessNote(Book book) {
  final source = sourceName(book.source);
  if (book.inApp) {
    return book.format == BookFormat.audio
        ? 'Listen in this app.'
        : 'Read in this app.';
  }
  return switch (book.access) {
    Access.borrow => 'Borrow it from $source. You need a free account there.',
    Access.printDisabled => 'Available at $source to people with a print disability.',
    Access.none => 'Listed at $source, which has no free copy to read.',
    Access.open => 'Read it free at $source.',
  };
}

class _BookCard extends StatelessWidget {
  const _BookCard({super.key, required this.work, required this.book});

  final Work work;
  final Book book;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final narrators = joinNames(book.narrators);
    final length = formatDuration(book.audioSeconds);
    final facts = [
      book.format == BookFormat.audio ? 'Audiobook' : 'Text',
      if (book.language != null) languageName(book.language),
      if (book.pages != null) '${book.pages} pages',
      ?length,
    ].join(' · ');
    final released = formatDate(book.releaseDate);
    final updated = formatDate(book.lastUpdated);
    final edition = [
      if (book.source == 'gutenberg') 'eBook #${book.sourceId}',
      if (released != null) 'Released $released',
      if (updated != null) 'Last updated $updated',
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Heading(sourceName(book.source), style: text.titleMedium),
            Text(facts, style: text.bodyMedium),
            if (narrators != null) Text('Read by $narrators', style: text.bodyMedium),
            if (edition.isNotEmpty) Text(edition, style: text.bodyMedium),
            if (book.originalPublication != null)
              Text('Original publication: ${book.originalPublication}', style: text.bodyMedium),
            if (book.credits != null) Text('Credits: ${book.credits}', style: text.bodySmall),
            const SizedBox(height: 4),
            Text(_accessNote(book), style: text.bodyMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                BookActionButton(key: Key('open-${book.key}'), work: work, book: book),
                TextButton(
                  key: Key('source-link-${book.key}'),
                  onPressed: () => Services.of(context).urlOpener.open(Uri.parse(book.url)),
                  child: Text('${sourceName(book.source)} page'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
