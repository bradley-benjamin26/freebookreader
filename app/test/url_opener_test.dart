// Links to outside pages come from source data, so only web links are opened (review 2026-10-11, #22).
import 'package:flutter_test/flutter_test.dart';
import 'package:free_book_reader/services/url_opener.dart';

void main() {
  test('refuses anything but http and https, without launching', () async {
    const opener = LauncherUrlOpener();
    for (final url in [
      'intent://scan/#Intent;scheme=zxing;end',
      'file:///etc/passwd',
      'javascript:alert(1)',
      'tel:+15551234567',
      'content://contacts/people',
      'relative/path.html',
    ]) {
      expect(await opener.open(Uri.parse(url)), isFalse, reason: url);
    }
  });

  test('knows which links it may open', () {
    expect(LauncherUrlOpener.isWebLink(Uri.parse('https://www.gutenberg.org/ebooks/1342')), isTrue);
    expect(LauncherUrlOpener.isWebLink(Uri.parse('HTTP://librivox.org/x')), isTrue);
    expect(LauncherUrlOpener.isWebLink(Uri.parse('https:///no-host')), isFalse);
    expect(LauncherUrlOpener.isWebLink(Uri.parse('ftp://example.org/x')), isFalse);
  });
}
