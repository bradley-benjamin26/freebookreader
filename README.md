# Free Book Reader

Find and read free books from Project Gutenberg, LibriVox, DOAB (Directory of Open Access Books) and Open Library, in one accessible app (WCAG 2.2 AA). See [spec.md](spec.md).

## Layout

| Path | What |
|---|---|
| `backend/` | FastAPI service that searches all four sources and merges the results |
| `app/` | Flutter app (tests written; `lib/` still to do) |
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
```

## License

MIT, see [LICENSE](LICENSE). This covers the code and documentation in this repository, except:

- `gutendex/` is vendored from [garethbjohnson/gutendex](https://github.com/garethbjohnson/gutendex) at commit `268b181` under its own MIT License (`gutendex/license`). Local changes: added tests in `books/tests.py` and `gutendex/test_settings.py`.
- `samples/` holds responses captured from Project Gutenberg (via Gutendex), LibriVox, Open Library and DOAB. That data belongs to those sources and is under their terms.
