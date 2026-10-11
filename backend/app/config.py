"""Settings from the environment (FBR_* variables) and wiring of the four-source search service."""
import json
import os
from dataclasses import dataclass
from datetime import timedelta
from pathlib import Path
from typing import Mapping

import httpx

from app.outage import OutageTracker
from app.publications import PublicationStore
from app.search import SearchService
from app.sources.doab import DoabSource
from app.sources.gutendex import GutendexSource
from app.sources.librivox import LibriVoxSource
from app.sources.openlibrary import OpenLibrarySource

VERSION = "0.1"
USER_AGENT = f"FreeBookReader/{VERSION}"
# The project's top-level .env: JSON with "name", "email" and "projectName". Only the project name
# and email are used (in the User-Agent); the personal name is never sent.
DEFAULT_ENV_FILE = Path(__file__).resolve().parents[2] / ".env"


def _read_env_file(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


@dataclass(frozen=True)
class Settings:
    gutendex_url: str = "http://localhost:8001"
    librivox_url: str = "https://librivox.org"
    openlibrary_url: str = "https://openlibrary.org"
    doab_url: str = "https://directory.doabooks.org"
    # EPUBs for the web reader (app/publications.py).
    gutenberg_url: str = "https://www.gutenberg.org"
    epub_cache_dir: Path = Path(__file__).resolve().parents[1] / "cache" / "epub"
    max_download_mb: float = 200
    epub_cache_mb: float = 2000
    search_timeout_seconds: float = 15
    outage_cooldown_hours: float = 24
    cors_origins: tuple[str, ...] = ("*",)
    # Open Library allows 3 requests/second instead of 1 when the User-Agent names the app and a contact.
    project_name: str | None = None
    contact: str | None = None

    @classmethod
    def from_env(cls, env: Mapping[str, str] | None = None) -> "Settings":
        """Settings from FBR_* variables. The .env file is FBR_ENV_FILE, or the project's top-level
        .env when reading the real environment (an explicit `env` mapping never reads it implicitly)."""
        if env is None:
            env = os.environ
            env_file = Path(env.get("FBR_ENV_FILE", DEFAULT_ENV_FILE))
        else:
            env_file = Path(env["FBR_ENV_FILE"]) if "FBR_ENV_FILE" in env else None
        file = _read_env_file(env_file) if env_file else {}
        get = lambda name, default: env.get(f"FBR_{name}", default)   # noqa: E731
        origins = get("CORS_ORIGINS", None)
        return cls(
            gutendex_url=get("GUTENDEX_URL", cls.gutendex_url),
            librivox_url=get("LIBRIVOX_URL", cls.librivox_url),
            openlibrary_url=get("OPENLIBRARY_URL", cls.openlibrary_url),
            doab_url=get("DOAB_URL", cls.doab_url),
            gutenberg_url=get("GUTENBERG_URL", cls.gutenberg_url),
            epub_cache_dir=Path(get("EPUB_CACHE_DIR", cls.epub_cache_dir)),
            max_download_mb=_number(get("MAX_DOWNLOAD_MB", cls.max_download_mb)),
            epub_cache_mb=_number(get("EPUB_CACHE_MB", cls.epub_cache_mb)),
            search_timeout_seconds=_number(get("SEARCH_TIMEOUT_SECONDS", cls.search_timeout_seconds)),
            outage_cooldown_hours=_number(get("OUTAGE_COOLDOWN_HOURS", cls.outage_cooldown_hours)),
            cors_origins=tuple(o.strip() for o in origins.split(",")) if origins else cls.cors_origins,
            project_name=file.get("projectName") or None,
            contact=get("CONTACT", None) or file.get("email") or None,
        )

    @property
    def user_agent(self) -> str:
        # A product token cannot contain spaces: "Free Book Reader" -> "FreeBookReader".
        name = "".join((self.project_name or "").split())
        product = f"{name}/{VERSION}" if name else USER_AGENT
        return f"{product} ({self.contact})" if self.contact else product


def _number(value) -> float:
    number = float(value)
    return int(number) if number.is_integer() else number


def build_http_client(settings: Settings) -> httpx.Client:
    return httpx.Client(
        timeout=settings.search_timeout_seconds,
        follow_redirects=True,
        headers={"User-Agent": settings.user_agent},
    )


def build_search_service(settings: Settings, client: httpx.Client) -> SearchService:
    sources = [
        GutendexSource(client=client, base_url=settings.gutendex_url),
        LibriVoxSource(client=client, base_url=settings.librivox_url),
        OpenLibrarySource(client=client, base_url=settings.openlibrary_url),
        DoabSource(client=client, base_url=settings.doab_url),
    ]
    outage = OutageTracker(cooldown=timedelta(hours=settings.outage_cooldown_hours))
    return SearchService(sources=sources, outage=outage, timeout_seconds=settings.search_timeout_seconds)


def build_publication_store(settings: Settings, client: httpx.Client) -> PublicationStore:
    megabyte = 1024 * 1024
    return PublicationStore(client=client, gutenberg_url=settings.gutenberg_url, cache_dir=settings.epub_cache_dir,
                            max_download_bytes=int(settings.max_download_mb * megabyte),
                            max_cache_bytes=int(settings.epub_cache_mb * megabyte))
