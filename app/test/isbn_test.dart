// Telling an ISBN from other search text (review 2026-10-11, #9).
import 'package:flutter_test/flutter_test.dart';
import 'package:free_book_reader/util/isbn.dart';

void main() {
  test('accepts ISBN-13 and ISBN-10 with a correct check digit, with or without hyphens and spaces', () {
    for (final isbn in ['9780140430721', '978-0-14-043072-1', ' 978 0 14 043072 1 ', '0141439513', '0-14-143951-3',
      '080442957X', '080442957x']) {
      expect(looksLikeIsbn(isbn), isTrue, reason: isbn);
    }
  });

  test('refuses a wrong check digit, a wrong length and ordinary text', () {
    for (final text in ['9780140430722', '0141439514', '12345', '1984', 'pride and prejudice',
      '978014043072a', '', '1234567890123', '97801404307211']) {
      expect(looksLikeIsbn(text), isFalse, reason: text);
    }
  });
}
