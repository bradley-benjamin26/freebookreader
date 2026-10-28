import 'package:flutter/material.dart';

import '../api/search_api.dart';
import '../app.dart';
import '../models/models.dart';
import '../util/format.dart';
import 'common.dart';
import 'details_page.dart';
import 'search_bar.dart';

/// Search results: the search box on top, filters (left on wide screens; on
/// phones the format under the search box and the rest in a sheet), then one row per work.
class ResultsPage extends StatefulWidget {
  const ResultsPage({super.key, required this.initialText, this.initialField = SearchField.anything});

  final String initialText;
  final SearchField initialField;

  @override
  State<ResultsPage> createState() => _ResultsPageState();
}

class _ResultsPageState extends State<ResultsPage> {
  static const wideLayout = 840.0;

  late SearchQuery _query = SearchQuery().withTerm(widget.initialField, widget.initialText);
  Set<String> _sources = {...sourceIds};
  Future<SearchResponse>? _results;

  // The search box moves between the wide and narrow layouts; the key keeps what is typed in it.
  final _searchBarKey = GlobalKey();

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

  /// The filters; [changed] lets the sheet redraw after a change.
  _Filters _filters({Key? key, bool format = true, bool sourcesAndLanguage = true, VoidCallback? changed}) =>
      _Filters(
        key: key,
        query: _query,
        sources: _sources,
        format: format,
        sourcesAndLanguage: sourcesAndLanguage,
        onToggleSource: (id) {
          _toggleSource(id);
          changed?.call();
        },
        onFormat: (format) => _search(
            format == null ? _query.copyWith(clearFormat: true) : _query.copyWith(format: format)),
        onLanguage: (language) {
          _search(language == null
              ? _query.copyWith(clearLanguage: true)
              : _query.copyWith(language: language));
          changed?.call();
        },
      );

  /// Phones: sources and language in a sheet. Changes apply at once, as on the page.
  Future<void> _openFilters(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => StatefulBuilder(
          builder: (sheetContext, setSheet) => SafeArea(
            child: SingleChildScrollView(
              key: const Key('filters-sheet'),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Heading('Filters', style: Theme.of(sheetContext).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  _filters(format: false, changed: () => setSheet(() {})),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      key: const Key('filters-done'),
                      onPressed: () => Navigator.pop(sheetContext),
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final searchBar = BookSearchBar(
      key: _searchBarKey,
      initialText: widget.initialText,
      initialField: widget.initialField,
      onSearch: (field, text) => _search(_query.withTerm(field, text)),
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
                        child: _filters(key: const Key('filters')),
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
        final narrowFilters = Wrap(
          key: const Key('filters'),
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _filters(sourcesAndLanguage: false),
            OutlinedButton.icon(
              key: const Key('filters-button'),
              onPressed: () => _openFilters(context),
              icon: const Icon(Icons.tune, semanticLabel: 'Filters'),
              label: Text(filterSummary(_query, _sources)),
            ),
          ],
        );
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [searchBar, const SizedBox(height: 8), narrowFilters, const SizedBox(height: 8), results],
          ),
        );
      }),
    );
  }
}

/// What the sources and language filters are set to, e.g. "2 of 5 sources · Spanish".
String filterSummary(SearchQuery query, Set<String> sources) {
  final which =
      sources.length == sourceIds.length ? 'All sources' : '${sources.length} of ${sourceIds.length} sources';
  return '$which · ${query.language == null ? 'Any language' : languageName(query.language)}';
}

class _Filters extends StatelessWidget {
  const _Filters({
    super.key,
    required this.query,
    required this.sources,
    required this.onToggleSource,
    required this.onFormat,
    required this.onLanguage,
    this.format = true,
    this.sourcesAndLanguage = true,
  });

  // Which parts to draw: both on a wide screen; on a phone the format on the page, the rest in a sheet.
  final bool format;
  final bool sourcesAndLanguage;

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
        if (sourcesAndLanguage) group('Sources', [
          for (final id in sourceIds)
            FilterChip(
              key: Key('filter-source-$id'),
              label: Text(sourceName(id)),
              selected: sources.contains(id),
              onSelected: (_) => onToggleSource(id),
            ),
        ]),
        if (format) group('Format', [
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
        // Without a label, a chosen language is announced as just "French, button".
        if (sourcesAndLanguage) Semantics(
          label: 'Language',
          child: DropdownButton<String?>(
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
      final message = switch (error) {
        SearchException(isTimeout: true) => 'The search took too long.',
        SearchException(isRejected: true) =>
          "This search can't be run. Shorten it or change the filters.",
        _ => 'The search did not work. Check your connection.',
      };
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
    final searched = query.searchedText;
    final notice = _skippedNotice(response);
    // Not a live region: the count or no-results already announces the search.
    final collectionNote = _nothingMatches(query, response.works)
        ? Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              "Nothing here matches by title or author. This app searches books that are out of copyright, "
              "openly licensed or free to borrow, so many recent books aren't included.",
              key: const Key('collection-note'),
              style: text.bodyMedium,
            ),
          )
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (notice != null)
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: LiveRegion(
                key: const Key('unavailable-notice'),
                child: Text(
                  notice,
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
          ),
        ?collectionNote,
        if (response.works.isNotEmpty) ...[
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
          for (final work in response.works) ResultRow(work: work, query: query),
        ],
      ],
    );
  }
}

/// True when no result shows the searched words in its title or author (or there are none), so the
/// person may be looking for a book these catalogs do not have. Never for subject or ISBN searches.
bool _nothingMatches(SearchQuery query, List<Work> works) {
  if (query.q == null && query.title == null && query.author == null) return false;
  return works.every((work) => matchNote(query, work) != null);
}

/// What to tell the user about the sources missing from a search, worded by the reason: a source in an
/// outage is skipped for 24 hours, a slow one is asked again on the next search. Null when none is missing.
String? _skippedNotice(SearchResponse response) {
  List<String> named(Set<SkipReason> reasons) => [
        for (final id in response.unavailableSources)
          if (reasons.contains(response.reasonFor(id))) sourceName(id),
      ];
  final down = named({SkipReason.outage});
  final slow = named({SkipReason.timeout, SkipReason.busy});
  final failed = named({SkipReason.rejected, SkipReason.error});
  final parts = [
    if (down.isNotEmpty)
      '${joinNames(down)} did not answer, so some results may be missing. '
          'A source that is down is skipped for up to 24 hours.',
    if (slow.isNotEmpty)
      '${joinNames(slow)} ${slow.length == 1 ? 'was' : 'were'} too slow this time, so some results may '
          'be missing. Search again to ask ${slow.length == 1 ? 'it' : 'them'} again.',
    if (failed.isNotEmpty)
      '${joinNames(failed)} could not run this search, so some results may be missing.',
  ];
  return parts.isEmpty ? null : parts.join(' ');
}

/// One work: cover, title, authors, sources, formats, and a button that goes
/// straight to the best way in. Tapping the row opens the details page.
class ResultRow extends StatelessWidget {
  const ResultRow({super.key, required this.work, required this.query});

  final Work work;
  final SearchQuery query;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final best = work.bestBook;
    final formats = [
      if (work.formats.contains('text')) 'Text',
      if (work.formats.contains('audio')) 'Audio',
    ].join(' and ');
    final note = matchNote(query, work);
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
                    if (note != null) Text(note, key: Key('result-match-${work.id}'), style: text.bodySmall),
                    Text([if (formats.isNotEmpty) formats, languageName(work.language)].join(' · '),
                        style: text.bodySmall),
                    if (best != null) ...[
                      BookActionButton(key: Key('open-${work.id}'), work: work, book: best),
                      if (bookSummary(best) case final summary?)
                        Text(summary, key: Key('result-edition-${work.id}'), style: text.bodySmall),
                      Text(accessNote(best), key: Key('result-access-${work.id}'), style: text.bodySmall),
                    ],
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
