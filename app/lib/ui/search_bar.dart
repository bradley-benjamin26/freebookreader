import 'package:flutter/material.dart';

import '../models/models.dart';
import 'common.dart';

const emptySearchMessage = 'Enter a title, author or topic to search.';

/// The longest text the backend accepts (it answers 422 above this).
const maxSearchLength = 300;

const _fieldNames = {
  SearchField.anything: 'Anything',
  SearchField.title: 'Title',
  SearchField.author: 'Author',
  SearchField.subject: 'Subject',
  SearchField.isbn: 'ISBN',
};

/// The search box, a dropdown of what to search in (anything, title, author, subject or ISBN), and the
/// button. Calls [onSearch] with the field and the trimmed text, or explains why nothing happened when
/// the box is empty or the text is longer than [maxSearchLength].
class BookSearchBar extends StatefulWidget {
  const BookSearchBar({
    super.key,
    required this.onSearch,
    this.initialText = '',
    this.initialField = SearchField.anything,
  });

  final void Function(SearchField field, String text) onSearch;
  final String initialText;
  final SearchField initialField;

  @override
  State<BookSearchBar> createState() => _BookSearchBarState();
}

class _BookSearchBarState extends State<BookSearchBar> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialText);
  late SearchField _field = widget.initialField;
  bool _showEmptyMessage = false;
  int? _tooLongBy; // the length of the text that was refused

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    final tooLong = text.length > maxSearchLength;
    setState(() {
      _showEmptyMessage = text.isEmpty;
      _tooLongBy = tooLong ? text.length : null;
    });
    if (text.isNotEmpty && !tooLong) widget.onSearch(_field, text);
  }

  @override
  Widget build(BuildContext context) {
    final searchIn = Semantics(
      container: true,
      label: 'Search in',
      child: DropdownButton<SearchField>(
        key: const Key('search-in'),
        value: _field,
        style: Theme.of(context).textTheme.bodyLarge, // the default, titleMedium, is the title serif
        underline: const SizedBox.shrink(),
        items: [
          for (final entry in _fieldNames.entries)
            DropdownMenuItem(key: Key('search-in-${entry.key.name}'), value: entry.key, child: Text(entry.value)),
        ],
        onChanged: (field) => setState(() => _field = field ?? _field),
      ),
    );
    final field = Expanded(
      // One semantics node that starts at the field itself.
      child: MergeSemantics(
        child: TextField(
          key: const Key('search-field'),
          controller: _controller,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _submit(),
          onChanged: (text) {
            if (_tooLongBy != null && text.trim().length <= maxSearchLength) {
              setState(() => _tooLongBy = null);
            }
          },
          decoration: const InputDecoration(labelText: 'Search books', border: OutlineInputBorder()),
        ),
      ),
    );
    final submit = FilledButton(key: const Key('search-submit'), onPressed: _submit, child: const Text('Search'));
    return LayoutBuilder(
      builder: (context, constraints) {
        // Too narrow for all three in a row: the choice goes on its own line above.
        final narrow = constraints.maxWidth < MediaQuery.textScalerOf(context).scale(320);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (narrow) Align(alignment: Alignment.centerLeft, child: searchIn),
            Row(
              children: [
                if (!narrow) ...[searchIn, const SizedBox(width: 8)],
                field,
                const SizedBox(width: 8),
                submit,
              ],
            ),
            if (_tooLongBy != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: LiveRegion(
                  key: const Key('search-too-long'),
                  child: Text(
                    'A search can have at most $maxSearchLength characters. This one has $_tooLongBy.',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              ),
            if (_showEmptyMessage)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: LiveRegion(
                  child: Text(emptySearchMessage, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              ),
          ],
        );
      },
    );
  }
}
