import 'package:flutter/material.dart';

import '../api/search_api.dart';
import '../app.dart';
import '../models/models.dart';
import '../util/format.dart';
import 'common.dart';
import 'details_page.dart';
import 'search_bar.dart';

/// Search results: the search box on top, filters (left on wide screens, under
/// the search box on phones), then one row per work.
class ResultsPage extends StatefulWidget {
  const ResultsPage({super.key, required this.initialText});

  final String initialText;

  @override
  State<ResultsPage> createState() => _ResultsPageState();
}

class _ResultsPageState extends State<ResultsPage> {
  static const wideLayout = 840.0;

  late SearchQuery _query = SearchQuery(q: widget.initialText);
  Set<String> _sources = {...sourceIds};
  Future<SearchResponse>? _results;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _results ??= _run();
  }

  Future<SearchResponse> _run() => Services.of(context).api.search(_query);

  void _search(SearchQuery query) => setState(() {
        _query = query;
        _results = _run();
      });

  void _toggleSource(String id) {
    final next = {..._sources};
    if (!next.remove(id)) next.add(id);
    if (next.isEmpty) return; // at least one source stays selected
    _sources = next;
    _search(next.length == sourceIds.length
        ? _query.copyWith(clearSources: true)
        : _query.copyWith(sources: sourceIds.where(next.contains).toList()));
  }

  @override
  Widget build(BuildContext context) {
    final searchBar = BookSearchBar(
      initialText: widget.initialText,
      onSearch: (text) => _search(_query.copyWith(q: text)),
    );
    final filters = _Filters(
      key: const Key('filters'),
      query: _query,
      sources: _sources,
      onToggleSource: _toggleSource,
      onFormat: (format) => _search(
          format == null ? _query.copyWith(clearFormat: true) : _query.copyWith(format: format)),
      onLanguage: (language) => _search(language == null
          ? _query.copyWith(clearLanguage: true)
          : _query.copyWith(language: language)),
    );
    final results = FutureBuilder<SearchResponse>(
      future: _results,
      builder: (context, snapshot) => _ResultsBody(
        query: _query,
        snapshot: snapshot,
        onRetry: () => _search(_query),
      ),
    );

    return Scaffold(
      key: const Key('results-page'),
      appBar: AppBar(
        title: Heading('Search results', key: const Key('results-heading'), maxLines: 1),
      ),
      body: LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth >= wideLayout) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(padding: const EdgeInsets.all(16), child: searchBar),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 280,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: filters,
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(right: 16, bottom: 16),
                        child: results,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [searchBar, const SizedBox(height: 8), filters, const SizedBox(height: 8), results],
          ),
        );
      }),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    super.key,
    required this.query,
    required this.sources,
    required this.onToggleSource,
    required this.onFormat,
    required this.onLanguage,
  });

  final SearchQuery query;
  final Set<String> sources;
  final ValueChanged<String> onToggleSource;
  final ValueChanged<BookFormat?> onFormat;
  final ValueChanged<String?> onLanguage;

  @override
  Widget build(BuildContext context) {
    Widget group(String label, List<Widget> children) => Semantics(
          container: true,
          label: label,
          explicitChildNodes: true,
          child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: children),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        group('Sources', [
          for (final id in sourceIds)
            FilterChip(
              key: Key('filter-source-$id'),
              label: Text(sourceName(id)),
              selected: sources.contains(id),
              onSelected: (_) => onToggleSource(id),
            ),
        ]),
        group('Format', [
          for (final (key, label, format) in [
            ('all', 'All formats', null),
            ('text', 'Text', BookFormat.text),
            ('audio', 'Audio', BookFormat.audio),
          ])
            ChoiceChip(
              key: Key('filter-format-$key'),
              label: Text(label),
              selected: query.format == format,
              onSelected: (_) => onFormat(format),
            ),
        ]),
        DropdownButton<String?>(
          key: const Key('filter-language'),
          isExpanded: true,
          value: query.language,
          onChanged: onLanguage,
          items: [
            const DropdownMenuItem(value: null, child: Text('Any language')),
            for (final entry in languageNames.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
        ),
      ],
    );
  }
}

class _ResultsBody extends StatelessWidget {
  const _ResultsBody({required this.query, required this.snapshot, required this.onRetry});

  final SearchQuery query;
  final AsyncSnapshot<SearchResponse> snapshot;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (snapshot.connectionState != ConnectionState.done) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
          child: LiveRegion(
            key: Key('searching'),
            child: CircularProgressIndicator(semanticsLabel: 'Searching'),
          ),
        ),
      );
    }
    if (snapshot.hasError) {
      final error = snapshot.error;
      final message = error is SearchException && error.isTimeout
          ? 'The search took too long.'
          : 'The search did not work. Check your connection.';
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LiveRegion(key: const Key('search-error'), child: Text(message, style: text.bodyLarge)),
            const SizedBox(height: 8),
            FilledButton(key: const Key('retry'), onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      );
    }
    final response = snapshot.data!;
    final searched = query.q ?? '';
    final unavailable = response.unavailableSources.map(sourceName).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (unavailable.isNotEmpty)
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: LiveRegion(
                key: const Key('unavailable-notice'),
                child: Text(
                  '${joinNames(unavailable)} did not answer, so some results may be missing. '
                  'A source that is down is skipped for up to 24 hours.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSecondaryContainer),
                ),
              ),
            ),
          ),
        if (response.works.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: LiveRegion(
              key: const Key('no-results'),
              child: Text('No results for "$searched". Try other words or fewer filters.',
                  style: text.bodyLarge),
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: LiveRegion(
              key: const Key('result-count'),
              child: Text(
                '${response.works.length} ${response.works.length == 1 ? 'result' : 'results'} for "$searched"',
                style: text.titleMedium,
              ),
            ),
          ),
          for (final work in response.works) ResultRow(work: work),
        ],
      ],
    );
  }
}

/// One work: cover, title, authors, sources, formats, and a button that goes
/// straight to the best way in. Tapping the row opens the details page.
class ResultRow extends StatelessWidget {
  const ResultRow({super.key, required this.work});

  final Work work;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final best = work.bestBook;
    final formats = [
      if (work.formats.contains('text')) 'Text',
      if (work.formats.contains('audio')) 'Audio',
    ].join(' and ');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('result-${work.id}'),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => DetailsPage(work: work))),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Cover(key: const Key('cover'), title: work.title, url: work.coverUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(work.title, style: text.titleMedium),
                    Text(formatAuthors(work.authors), style: text.bodyMedium),
                    Text(work.sources.map(sourceName).join(', '), style: text.bodySmall),
                    if (formats.isNotEmpty) Text(formats, style: text.bodySmall),
                    if (best != null)
                      BookActionButton(key: Key('open-${work.id}'), work: work, book: best),
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
