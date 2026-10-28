// "Can bookmark in a book to mark where they left off. Until accounts exist,
// bookmarks are stored on the device only."
import 'package:flutter_test/flutter_test.dart';
import 'package:free_book_reader/storage/bookmark_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<BookmarkStore> newStore([Map<String, Object> initial = const {}]) async {
  SharedPreferences.setMockInitialValues(initial);
  return BookmarkStore(await SharedPreferences.getInstance());
}

void main() {
  test('a book with no bookmark returns null', () async {
    final store = await newStore();
    expect(store.load('gutenberg:1342'), isNull);
  });

  test('saves and loads a bookmark', () async {
    final store = await newStore();
    await store.save('gutenberg:1342', const Bookmark(progress: 0.42));
    expect(store.load('gutenberg:1342')?.progress, closeTo(0.42, 1e-9));
  });

  test("keeps the reader engine's locator alongside the progress", () async {
    final store = await newStore();
    await store.save('gutenberg:1342', const Bookmark(progress: 0.42, locator: '{"href":"c3.xhtml"}'));
    expect(store.load('gutenberg:1342')?.locator, '{"href":"c3.xhtml"}');
  });

  test('a bookmark saved before locators existed loads without one', () async {
    final store = await newStore({'bookmark:gutenberg:1342': '{"progress":0.42}'});
    final bookmark = store.load('gutenberg:1342')!;
    expect(bookmark.progress, closeTo(0.42, 1e-9));
    expect(bookmark.locator, isNull);
  });

  test('bookmarks survive a restart (a new store over the same preferences)', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await BookmarkStore(prefs).save('doab:20.500.12854/95506', const Bookmark(progress: 0.9));
    final reopened = BookmarkStore(await SharedPreferences.getInstance());
    expect(reopened.load('doab:20.500.12854/95506')?.progress, closeTo(0.9, 1e-9));
  });

  test('bookmarks are kept per book', () async {
    final store = await newStore();
    await store.save('gutenberg:1', const Bookmark(progress: 0.1));
    await store.save('gutenberg:2', const Bookmark(progress: 0.2));
    expect(store.load('gutenberg:1')?.progress, closeTo(0.1, 1e-9));
    expect(store.load('gutenberg:2')?.progress, closeTo(0.2, 1e-9));
  });

  test('saving again replaces the earlier bookmark', () async {
    final store = await newStore();
    await store.save('gutenberg:1', const Bookmark(progress: 0.1));
    await store.save('gutenberg:1', const Bookmark(progress: 0.7));
    expect(store.load('gutenberg:1')?.progress, closeTo(0.7, 1e-9));
  });

  test('removing a bookmark', () async {
    final store = await newStore();
    await store.save('gutenberg:1', const Bookmark(progress: 0.1));
    await store.remove('gutenberg:1');
    expect(store.load('gutenberg:1'), isNull);
  });

  test('progress is clamped to 0..1', () {
    expect(const Bookmark(progress: -3).progress, 0);
    expect(const Bookmark(progress: 4).progress, 1);
  });

  test('corrupt stored data is treated as no bookmark', () async {
    final store = await newStore({'bookmark:gutenberg:1': 'not json'});
    expect(store.load('gutenberg:1'), isNull);
  });

  test('lists every saved book key', () async {
    final store = await newStore();
    await store.save('gutenberg:1', const Bookmark(progress: 0.1));
    await store.save('doab:9', const Bookmark(progress: 0.5));
    expect(store.savedBookKeys()..sort(), ['doab:9', 'gutenberg:1']);
  });

  test('only touches its own keys in the shared preferences', () async {
    final store = await newStore({'reader_settings': 'x', 'other': 'y'});
    await store.save('gutenberg:1', const Bookmark(progress: 0.1));
    expect(store.savedBookKeys(), ['gutenberg:1']);
  });

  // Persona round one: the reader reopens where it stopped, without a bookmark.
  test('keeps a last place apart from the bookmark', () async {
    final store = await newStore();
    await store.saveLastPlace('gutenberg:1', const Bookmark(progress: 0.5, locator: 'x'));
    final place = store.loadLastPlace('gutenberg:1')!;
    expect(place.progress, closeTo(0.5, 1e-9));
    expect(place.locator, 'x');
    expect(store.load('gutenberg:1'), isNull);
    expect(store.savedBookKeys(), isEmpty);
  });

  test('a damaged last place loads as none', () async {
    final store = await newStore({'lastplace:gutenberg:1': 'not json'});
    expect(store.loadLastPlace('gutenberg:1'), isNull);
  });
}
