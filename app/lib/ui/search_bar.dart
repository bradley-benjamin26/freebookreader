import 'package:flutter/material.dart';

import 'common.dart';

const emptySearchMessage = 'Enter a title, author or topic to search.';

/// The search box and its button. Calls [onSearch] with the trimmed text, or
/// explains why nothing happened when the box is empty.
class BookSearchBar extends StatefulWidget {
  const BookSearchBar({super.key, required this.onSearch, this.initialText = ''});

  final ValueChanged<String> onSearch;
  final String initialText;

  @override
  State<BookSearchBar> createState() => _BookSearchBarState();
}

class _BookSearchBarState extends State<BookSearchBar> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialText);
  bool _showEmptyMessage = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    setState(() => _showEmptyMessage = text.isEmpty);
    if (text.isNotEmpty) widget.onSearch(text);
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
