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

/// The search box, a choice of what to search in (anything, title, author, subject or ISBN), and the
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
  int? _tooLongBy;   // the length of the text that was refused

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
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
                  decoration: const InputDecoration(
                    labelText: 'Search books',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const Key('search-submit'),
              onPressed: _submit,
              child: const Text('Search'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Semantics(
          key: const Key('search-in'),
          container: true,
          label: 'Search in',
          explicitChildNodes: true,
          child: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final entry in _fieldNames.entries)
                ChoiceChip(
                  key: Key('search-in-${entry.key.name}'),
                  label: Text(entry.value),
                  selected: _field == entry.key,
                  onSelected: (_) => setState(() => _field = entry.key),
                ),
            ],
          ),
        ),
        if (_tooLongBy != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: LiveRegion(
              key: const Key('search-too-long'),
              child: Text(
                  'A search can have at most $maxSearchLength characters. This one has $_tooLongBy.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          ),
        if (_showEmptyMessage)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: LiveRegion(
              child: Text(emptySearchMessage,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          ),
      ],
    );
  }
}
