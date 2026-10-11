// The app's models mirror the backend's JSON (backend/app/models.py and
// backend/app/search.py). Unknown enum values are rejected, not guessed.

enum BookFormat { text, audio }

enum Access { open, borrow, printDisabled, none }

enum ReadingMode { inApp, external }

T _parseEnum<T>(Map<String, T> values, Object? raw, String field) {
  final value = values[raw];
  if (value == null) throw FormatException('Unknown $field: $raw');
  return value;
}

const _formats = {'text': BookFormat.text, 'audio': BookFormat.audio};
const _access = {
  'open': Access.open,
  'borrow': Access.borrow,
  'print_disabled': Access.printDisabled,
  'none': Access.none,
};
const _modes = {'in_app': ReadingMode.inApp, 'external': ReadingMode.external};

List<String> _strings(Object? raw) => (raw as List?)?.cast<String>().toList() ?? const [];

Map<String, List<String>> _stringLists(Object? raw) => {
      for (final entry in ((raw as Map?) ?? const {}).entries)
        entry.key as String: _strings(entry.value),
    };

/// How a book is opened: in the app (with [kind] html, epub, text, pdf or
/// audio) or at its source.
class ReadingOptions {
  const ReadingOptions({required this.mode, required this.kind, required this.url, this.publication});

  factory ReadingOptions.fromJson(Map<String, dynamic> json) => ReadingOptions(
        mode: _parseEnum(_modes, json['mode'], 'reading mode'),
        kind: json['kind'] as String?,
        url: json['url'] as String,
        publication: json['publication'] as String?,
      );

  final ReadingMode mode;
  final String? kind;
  final String url;

  /// Path on the backend of a Readium manifest for the web reader
  /// (`/publications/gutenberg/<id>/manifest.json`), or null.
  final String? publication;
}

class Chapter {
  const Chapter({required this.title, required this.url, this.durationSeconds});

  factory Chapter.fromJson(Map<String, dynamic> json) => Chapter(
        title: json['title'] as String,
        url: json['url'] as String,
        durationSeconds: json['duration_seconds'] as int?,
      );

  final String title;
  final String url;
  final int? durationSeconds;
}

/// One record from one source.
class Book {
  const Book({
    required this.source,
    required this.sourceId,
    required this.title,
    this.authors = const [],
    this.narrators = const [],
    this.contributors = const [],
    this.language,
    required this.format,
    this.pages,
    this.audioSeconds,
    this.identifiers = const {},
    required this.url,
    this.coverUrl,
    this.content = const {},
    this.chapters = const [],
    required this.access,
    required this.reading,
  });

  factory Book.fromJson(Map<String, dynamic> json) => Book(
        source: json['source'] as String,
        sourceId: json['source_id'] as String,
        title: json['title'] as String,
        authors: _strings(json['authors']),
        narrators: _strings(json['narrators']),
        contributors: _strings(json['contributors']),
        language: json['language'] as String?,
        format: _parseEnum(_formats, json['format'], 'format'),
        pages: json['pages'] as int?,
        audioSeconds: json['audio_seconds'] as int?,
        identifiers: _stringLists(json['identifiers']),
        url: json['url'] as String,
        coverUrl: json['cover_url'] as String?,
        content: ((json['content'] as Map?) ?? const {}).cast<String, String>(),
        chapters: ((json['chapters'] as List?) ?? const [])
            .map((c) => Chapter.fromJson(c as Map<String, dynamic>))
            .toList(),
        access: _parseEnum(_access, json['access'], 'access'),
        reading: ReadingOptions.fromJson(json['reading'] as Map<String, dynamic>),
      );

  final String source;
  final String sourceId;
  final String title;
  final List<String> authors;
  final List<String> narrators;
  final List<String> contributors;
  final String? language;
  final BookFormat format;
  final int? pages;
  final int? audioSeconds;
  final Map<String, List<String>> identifiers;
  final String url;
  final String? coverUrl;

  /// Download links by MIME type.
  final Map<String, String> content;
  final List<Chapter> chapters;
  final Access access;
  final ReadingOptions reading;

  /// Unique across sources, e.g. `gutenberg:1342`. Bookmarks are stored under it.
  String get key => '$source:$sourceId';

  bool get inApp => reading.mode == ReadingMode.inApp;
}

/// Records from several sources that are the same work.
class Work {
  const Work({
    required this.id,
    required this.title,
    this.authors = const [],
    this.language,
    this.sources = const [],
    this.sourceIds = const {},
    this.identifiers = const {},
    this.urls = const [],
    this.coverUrl,
    this.formats = const [],
    this.books = const [],
  });

  factory Work.fromJson(Map<String, dynamic> json) => Work(
        id: json['id'] as String,
        title: json['title'] as String,
        authors: _strings(json['authors']),
        language: json['language'] as String?,
        sources: _strings(json['sources']),
        sourceIds: _stringLists(json['source_ids']),
        identifiers: _stringLists(json['identifiers']),
        urls: _strings(json['urls']),
        coverUrl: json['cover_url'] as String?,
        formats: _strings(json['formats']),
        books: ((json['books'] as List?) ?? const [])
            .map((b) => Book.fromJson(b as Map<String, dynamic>))
            .toList(),
      );

  final String id;
  final String title;
  final List<String> authors;
  final String? language;
  final List<String> sources;
  final Map<String, List<String>> sourceIds;
  final Map<String, List<String>> identifiers;
  final List<String> urls;
  final String? coverUrl;
  final List<String> formats;
  final List<Book> books;

  List<Book> get textBooks => books.where((b) => b.format == BookFormat.text).toList();
  List<Book> get audioBooks => books.where((b) => b.format == BookFormat.audio).toList();

  /// Recordings that can play alongside [book]: audio in the app, in the same
  /// language as the text.
  List<Book> recordingsFor(Book book) {
    if (book.language == null) return const [];
    return audioBooks.where((a) => a.inApp && a.language == book.language).toList();
  }

  /// The best way in: read in the app, else listen in the app, else the first
  /// book (opened at its source).
  Book? get bestBook =>
      textBooks.where((b) => b.inApp).firstOrNull ??
      audioBooks.where((b) => b.inApp).firstOrNull ??
      books.firstOrNull;
}

class SearchResponse {
  const SearchResponse({required this.works, required this.unavailableSources});

  factory SearchResponse.fromJson(Map<String, dynamic> json) => SearchResponse(
        works: ((json['works'] as List?) ?? const [])
            .map((w) => Work.fromJson(w as Map<String, dynamic>))
            .toList(),
        unavailableSources: _strings(json['unavailable_sources']),
      );

  final List<Work> works;

  /// Sources that did not answer this search.
  final List<String> unavailableSources;
}

/// One entry of the backend's `/sources`.
class SourceInfo {
  const SourceInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.howItWorks,
    required this.howToAccess,
    required this.websiteUrl,
    required this.donationUrl,
    required this.formats,
    required this.inApp,
  });

  factory SourceInfo.fromJson(Map<String, dynamic> json) => SourceInfo(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String,
        howItWorks: json['how_it_works'] as String,
        howToAccess: json['how_to_access'] as String,
        websiteUrl: json['website_url'] as String,
        donationUrl: json['donation_url'] as String,
        formats: _strings(json['formats']),
        inApp: json['in_app'] as bool,
      );

  final String id;
  final String name;
  final String description;
  final String howItWorks;
  final String howToAccess;
  final String websiteUrl;
  final String donationUrl;
  final List<String> formats;
  final bool inApp;
}

class SearchQuery {
  SearchQuery({
    this.q,
    this.title,
    this.author,
    this.keyword,
    this.isbn,
    this.language,
    this.format,
    this.sources,
    this.page = 1,
  });

  final String? q;
  final String? title;
  final String? author;
  final String? keyword;
  final String? isbn;

  /// ISO 639-1 code.
  final String? language;
  final BookFormat? format;

  /// Null searches every source.
  final List<String>? sources;
  final int page;

  static bool _filled(String? s) => s != null && s.trim().isNotEmpty;

  bool get isSearchable => [q, title, author, keyword, isbn].any(_filled);

  Map<String, String> toQueryParameters() => {
        for (final (name, value) in [
          ('q', q),
          ('title', title),
          ('author', author),
          ('keyword', keyword),
          ('isbn', isbn),
          ('language', language),
        ])
          if (_filled(value)) name: value!.trim(),
        if (format != null) 'format': format!.name,
        if (sources != null && sources!.isNotEmpty) 'sources': sources!.join(','),
        'page': '$page',
      };

  SearchQuery copyWith({
    String? q,
    String? title,
    String? author,
    String? keyword,
    String? isbn,
    String? language,
    BookFormat? format,
    List<String>? sources,
    int? page,
    bool clearLanguage = false,
    bool clearFormat = false,
    bool clearSources = false,
  }) =>
      SearchQuery(
        q: q ?? this.q,
        title: title ?? this.title,
        author: author ?? this.author,
        keyword: keyword ?? this.keyword,
        isbn: isbn ?? this.isbn,
        language: clearLanguage ? null : language ?? this.language,
        format: clearFormat ? null : format ?? this.format,
        sources: clearSources ? null : sources ?? this.sources,
        page: page ?? this.page,
      );
}
