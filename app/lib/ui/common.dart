import 'package:flutter/material.dart';

import '../app.dart';
import '../models/models.dart';
import '../reader/reader_page.dart';
import '../util/format.dart';
import 'audio_page.dart';

/// A page heading that screen readers announce as a heading.
class Heading extends StatelessWidget {
  const Heading(this.text, {super.key, this.style, this.textAlign, this.maxLines, this.level = 2});

  final String text;

  /// 1 for a page's title, 2 for its sections.
  final int level;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        header: true,
        headingLevel: level,
        child: Text(text,
            style: style,
            textAlign: textAlign,
            maxLines: maxLines,
            overflow: maxLines == null ? null : TextOverflow.ellipsis),
      );
}

/// A short page that scrolls. Unlike a ListView, it builds every child, so
/// everything on the page can be found and scrolled to.
class ScrollColumn extends StatelessWidget {
  const ScrollColumn({super.key, this.padding, required this.children});

  final EdgeInsetsGeometry? padding;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: padding,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );
}

/// A status message announced by screen readers when it changes.
class LiveRegion extends StatelessWidget {
  const LiveRegion({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Semantics(container: true, liveRegion: true, child: child);
}

/// A book cover, or a placeholder when there is none or it fails to load.
class Cover extends StatelessWidget {
  const Cover({super.key, required this.title, required this.url, this.width = 56});

  final String title;
  final String? url;
  final double width;

  @override
  Widget build(BuildContext context) {
    final height = width * 1.5;
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: width,
      height: height,
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(Icons.menu_book, size: width / 2, color: scheme.onSurfaceVariant),
    );
    return Semantics(
      container: true,
      image: true,
      label: 'Cover of $title',
      child: ExcludeSemantics(
        child: SizedBox(
          width: width,
          height: height,
          child: url == null
              ? placeholder
              : Image.network(
                  url!,
                  fit: BoxFit.cover,
                  excludeFromSemantics: true,
                  // gutenberg.org sends no CORS header; an <img> element does not need one.
                  webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                  errorBuilder: (_, _, _) => placeholder,
                ),
        ),
      ),
    );
  }
}

/// The button that opens a book. It shows a verb ("Read", "Borrow") and its
/// accessible name says which book and where, e.g. "Borrow Emma by Jane
/// Austen at Open Library". [detail] is added to that name, so a book card's button differs from the
/// details page's main button.
class BookActionButton extends StatelessWidget {
  const BookActionButton({super.key, required this.work, required this.book, this.detail});

  final Work work;
  final Book book;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: () => openBook(context, work, book),
      icon: Icon(book.inApp ? (book.format == BookFormat.audio ? Icons.headphones : Icons.menu_book)
          : Icons.open_in_new),
      label: Semantics(
        label: detail == null || detail!.isEmpty ? actionLabel(book) : '${actionLabel(book)}, $detail',
        excludeSemantics: true,
        child: Text(actionVerb(book)),
      ),
    );
  }
}

/// Opens [book] the way it can be read: the reader, the player, or its source.
Future<void> openBook(BuildContext context, Work work, Book book) async {
  final reading = book.reading;
  if (!book.inApp) {
    await Services.of(context).urlOpener.open(Uri.parse(reading.url));
    return;
  }
  final page = reading.kind == 'audio'
      ? AudioPage(work: work, book: book)
      : ReaderPage(work: work, book: book);
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
}
