# Free Book Reader

Find and read free books from Project Gutenberg, LibriVox, DOAB (Directory of Open Access Books) and Open Library, in one accessible app (WCAG 2.2 AA). See [spec.md](spec.md).

## Layout

| Path | What |
|---|---|
| `backend/` | FastAPI service that searches all four sources and merges the results |
| `app/` | Flutter app (Android, iOS, web) |
| `gutendex/` | Local Gutendex (Django) for searching Project Gutenberg; vendored, see below |
| `samples/` | Captured API responses |
| `api_*.documentation.md` | Notes on each source's API, with sample curl calls |
| `spec.md`, `decision_reader.md`, `externalSources.md` | Spec and decisions |

## Setup

Copy `.env.example` to `.env` and fill it in. It is JSON; the backend uses `projectName` and `email` in its User-Agent (Open Library allows a higher rate limit when a contact is given) and never sends `name`.

### Backend

```sh
cd backend
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt -r requirements-dev.txt
python -m pytest
uvicorn app.main:create_app --factory --port 8000
```

Settings are `FBR_*` environment variables; see [backend/tests/README.md](backend/tests/README.md).

### Gutendex

Needs Postgres. Copy `gutendex/gutendex/.env.template` to `gutendex/gutendex/.env` and fill it in, then:

```sh
cd gutendex
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt
python manage.py migrate
python manage.py updatecatalog   # downloads the Gutenberg catalog (~2 GB in catalog_files/)
python manage.py runserver 8001
python manage.py test books --settings=gutendex.test_settings   # tests use SQLite
```

### App

```sh
cd app
flutter pub get
flutter test
flutter run --dart-define=BACKEND_URL=http://localhost:8000
```

## Updating

The databases and installed packages are not in git, so `git pull` does not update them. After pulling:

```sh
cd gutendex && source venv/bin/activate
python manage.py migrate         # adds any new database columns; Gutendex fails without it
python manage.py updatecatalog   # fills new fields and refreshes the catalog
```

`migrate` is needed whenever a pull adds a file under `gutendex/books/migrations/`. Run `updatecatalog` after it when the new columns are filled from the catalog (for example `0006_book_edition_details`, 2026-10-10), or as part of the regular nightly refresh. If `requirements.txt` or `pubspec.yaml` changed, re-run `pip install -r requirements.txt` (in `backend/` add `-r requirements-dev.txt`) or `flutter pub get`.

## License

MIT, see [LICENSE](LICENSE). This covers the code and documentation in this repository, except:

- `gutendex/` is vendored from [garethbjohnson/gutendex](https://github.com/garethbjohnson/gutendex) at commit `268b181` under its own MIT License (`gutendex/license`). Local changes: added tests in `books/tests.py` and `gutendex/test_settings.py`, and edition details (`release_date`, `last_updated`, `credits`, `original_publication`) parsed from the RDF in `books/utils.py`, stored by migration `0006_book_edition_details` and returned by the API (`models.py`, `serializers.py`, `updatecatalog.py`). See [api_gutendex.documentation.md](api_gutendex.documentation.md).
- `samples/` holds responses captured from Project Gutenberg (via Gutendex), LibriVox, Open Library and DOAB. That data belongs to those sources and is under their terms.
