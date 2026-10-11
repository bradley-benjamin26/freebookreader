# Source targets
Use the documentaiton links to understand the apis.
## Project Gutenberg
Project Gutenberg will be the most complicated because it does not offer API access. Maybe it's not possible or should be left for another version. A tool will need to be build using the following documentation in order to query and serve up the books
documentation: https://github.com/garethbjohnson/gutendex

## DOAB (Directory of Open Access Books; replaces OAPEN)
Documentation: https://www.doabooks.org/en/librarians/doab-metadata

api url: https://directory.doabooks.org/rest/search?query=[search query] (rejects our IP; the backend uses OpenSearch and OAI-PMH instead, see api_doab.documentation.md)

## OAPEN Library (hosts most DOAB PDFs)
Documentation: https://www.oapen.org/librarians/metadata. see section:"Search the OAPEN Library using a REST API"

api url: https://library.oapen.org/rest/search?query=[search query]

Seems to only have PDF and a PDF viewer... so try to make that work

## LibriVox
api url: https://librivox.org/api/feed/audiobooks
documentation: https://librivox.org/api/info

## Open Library
documentation: https://openlibrary.org/docs, https://openlibrary.org/developers/api
python client library: https://github.com/internetarchive/openlibrary-client

# WCAG
Documentation: https://www.w3.org/TR/WCAG22/

# Reader libraries
See decision_reader.md.
flutter_readium: https://github.com/Notalib/flutter_readium
flutter_epub_viewer: https://pub.dev/packages/flutter_epub_viewer
just_audio (audiobook playback): https://pub.dev/packages/just_audio
audio_service (background audio): https://pub.dev/packages/audio_service
