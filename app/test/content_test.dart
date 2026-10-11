// Turning a book's HTML or plain text into paragraphs for our own renderer.
// Review 2026-10-11, #10: verse lost its line breaks and text outside <p> was dropped.
import 'package:flutter_test/flutter_test.dart';
import 'package:free_book_reader/reader/content.dart';
import 'package:free_book_reader/reader/pagination.dart';

void main() {
  group('htmlParagraphs', () {
    test('headings and paragraphs, in order, with whitespace folded', () {
      expect(htmlParagraphs('<h1>Chapter  I</h1>\n<p>It is\n a truth.</p><p>Next.</p>'),
          ['Chapter I', 'It is a truth.', 'Next.']);
    });

    test('<br> is a line break inside the paragraph', () {
      expect(htmlParagraphs('<p>Once upon a midnight dreary,<br>while I pondered,<br/>weak and weary</p>'),
          ['Once upon a midnight dreary,\nwhile I pondered,\nweak and weary']);
    });

    test('spaces around a line break do not stay', () {
      expect(htmlParagraphs('<p>one <br> two <br>\n three</p>'), ['one\ntwo\nthree']);
    });

    test('a break at the start or end of a paragraph is dropped', () {
      expect(htmlParagraphs('<p><br>line<br></p>'), ['line']);
    });

    test('verse in a div of spans is kept, one line each', () {
      expect(
          htmlParagraphs('<div class="poem"><div class="stanza"><span class="i0">First line</span><br/>'
              '<span class="i2">Second line</span><br/></div></div>'),
          ['First line\nSecond line']);
    });

    test('text in <pre> keeps its lines', () {
      expect(htmlParagraphs('<pre>Line one\n   Line two\nLine three</pre>'), ['Line one\nLine two\nLine three']);
    });

    test('list items, table cells, block quotes and small headings are kept', () {
      expect(
          htmlParagraphs('<ul><li>First</li><li>Second</li></ul>'
              '<table><tr><td>Cell A</td><td>Cell B</td></tr></table>'
              '<blockquote>Quoted without a paragraph</blockquote><h5>Small</h5><h6>Smaller</h6>'),
          ['First', 'Second', 'Cell A', 'Cell B', 'Quoted without a paragraph', 'Small', 'Smaller']);
    });

    test('a block inside a block splits the text around it', () {
      expect(htmlParagraphs('<div>Before <p>Inside</p> after</div>'), ['Before', 'Inside', 'after']);
    });

    test('inline markup stays in its paragraph', () {
      expect(htmlParagraphs('<p>A <em>very</em> <a href="#x">linked</a> word<span class="pagenum">[12]</span></p>'),
          ['A very linked word[12]']);
    });

    test("Project Gutenberg's header, footer, scripts and styles are left out", () {
      expect(
          htmlParagraphs('<style>p {}</style><script>var a;</script><section id="pg-header"><p>License</p></section>'
              '<p>The book.</p><div class="pg-boilerplate"><p>More license</p></div><section id="pg-footer"><p>End</p></section>'),
          ['The book.']);
    });

    test('empty paragraphs are dropped', () {
      expect(htmlParagraphs('<p> </p><p>&nbsp;</p><div><br></div><p>Text</p>'), ['Text']);
    });
  });

  group('textParagraphs', () {
    test('paragraphs are separated by blank lines; the lines of one are joined', () {
      expect(textParagraphs('One two\nthree.\n\nFour.\r\n\r\n\r\nFive.'), ['One two three.', 'Four.', 'Five.']);
    });
  });

  group('a line break in the word index', () {
    test('keeps words apart and counts each once', () {
      final book = BookText(['Once upon,\nwhile I', 'Next']);
      expect(book.text(0, book.length, '\n\n'), 'Once upon,\nwhile I\n\nNext');
      expect(book.length, 5);
    });
  });
}
