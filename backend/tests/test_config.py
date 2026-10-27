"""Wiring: settings from the environment and the five-source search service."""
import json

import httpx
import pytest

from app.config import Settings, build_http_client, build_search_service


def test_defaults():
    settings = Settings.from_env({})
    assert settings.gutendex_url == "http://localhost:8001"
    assert settings.librivox_url == "https://librivox.org"
    assert settings.openlibrary_url == "https://openlibrary.org"
    assert settings.doab_url == "https://directory.doabooks.org"
    assert settings.hathitrust_index.name == "hathitrust.sqlite"
    assert settings.hathitrust_index.parent.name == "cache"
    assert settings.hathitrust_file_list_url == "https://www.hathitrust.org/files/hathifiles/hathi_file_list.json"
    assert settings.search_timeout_seconds == 12
    assert settings.max_concurrent_searches == 20
    assert settings.search_admission_seconds == 3
    assert settings.outage_cooldown_hours == 24
    assert settings.search_cache_seconds == 300


def test_environment_overrides():
    settings = Settings.from_env({
        "FBR_GUTENDEX_URL": "http://gutendex:8000",
        "FBR_SEARCH_TIMEOUT_SECONDS": "5",
        "FBR_MAX_CONCURRENT_SEARCHES": "3",
        "FBR_SEARCH_ADMISSION_SECONDS": "1.5",
        "FBR_OUTAGE_COOLDOWN_HOURS": "1",
        "FBR_SEARCH_CACHE_SECONDS": "0",
    })
    assert settings.gutendex_url == "http://gutendex:8000"
    assert settings.search_timeout_seconds == 5
    assert settings.max_concurrent_searches == 3
    assert settings.search_admission_seconds == 1.5
    assert settings.outage_cooldown_hours == 1
    assert settings.search_cache_seconds == 0


class TestEnvFile:
    """The project's top-level .env is JSON: {"name", "email", "projectName"}."""

    @pytest.fixture
    def env_file(self, tmp_path):
        path = tmp_path / ".env"
        path.write_text(json.dumps({"name": "A Person", "email": "someone@example.org",
                                    "projectName": "Free Book Reader"}))
        return path

    def test_user_agent_names_the_project_and_contact(self, env_file):
        settings = Settings.from_env({"FBR_ENV_FILE": str(env_file)})
        assert settings.user_agent == "FreeBookReader/0.1 (someone@example.org)"

    def test_the_personal_name_is_not_sent(self, env_file):
        assert "A Person" not in Settings.from_env({"FBR_ENV_FILE": str(env_file)}).user_agent

    def test_fbr_contact_overrides_the_file(self, env_file):
        settings = Settings.from_env({"FBR_ENV_FILE": str(env_file), "FBR_CONTACT": "ops@example.org"})
        assert settings.user_agent == "FreeBookReader/0.1 (ops@example.org)"

    def test_missing_file_uses_the_plain_user_agent(self, tmp_path):
        settings = Settings.from_env({"FBR_ENV_FILE": str(tmp_path / "nope")})
        assert settings.user_agent == "FreeBookReader/0.1"

    def test_explicit_env_does_not_read_the_project_file(self):
        assert Settings.from_env({}).user_agent == "FreeBookReader/0.1"

    def test_the_client_sends_the_user_agent(self, env_file):
        client = build_http_client(Settings.from_env({"FBR_ENV_FILE": str(env_file)}))
        assert client.headers["User-Agent"] == "FreeBookReader/0.1 (someone@example.org)"


def test_service_has_all_five_sources():
    service = build_search_service(Settings.from_env({}), client=httpx.Client())
    assert sorted(s.name for s in service.sources) == ["doab", "gutenberg", "hathitrust", "librivox", "openlibrary"]
    assert service.timeout_seconds == 12
    assert service.cache_seconds == 300


def test_hathitrust_settings_come_from_the_environment():
    settings = Settings.from_env({"FBR_HATHITRUST_INDEX": "/data/hathi.sqlite",
                                  "FBR_HATHITRUST_FILE_LIST_URL": "https://files.test/list.json"})
    assert str(settings.hathitrust_index) == "/data/hathi.sqlite"
    assert settings.hathitrust_file_list_url == "https://files.test/list.json"


def test_the_hathitrust_source_reads_the_configured_index(tmp_path):
    settings = Settings.from_env({"FBR_HATHITRUST_INDEX": str(tmp_path / "h.sqlite")})
    service = build_search_service(settings, client=httpx.Client())
    source = next(s for s in service.sources if s.name == "hathitrust")
    assert source.index.path == tmp_path / "h.sqlite"


def test_service_uses_the_configured_gutendex_url(recorder):
    rec = recorder(json={"count": 0, "next": None, "previous": None, "results": []})
    service = build_search_service(
        Settings.from_env({"FBR_GUTENDEX_URL": "http://gutendex.test"}), client=rec.client)
    gutenberg = next(s for s in service.sources if s.name == "gutenberg")
    from app.models import SearchQuery
    gutenberg.search(SearchQuery(q="x"))
    assert rec.last.url.host == "gutendex.test"


def test_publication_settings():
    settings = Settings.from_env({})
    assert settings.gutenberg_url == "https://www.gutenberg.org"
    assert settings.max_download_mb == 200
    assert settings.epub_cache_mb == 2000
    custom = Settings.from_env({"FBR_GUTENBERG_URL": "https://mirror.example", "FBR_EPUB_CACHE_DIR": "/tmp/x",
                                "FBR_MAX_DOWNLOAD_MB": "50", "FBR_EPUB_CACHE_MB": "100"})
    assert custom.gutenberg_url == "https://mirror.example"
    assert str(custom.epub_cache_dir) == "/tmp/x"
    assert custom.max_download_mb == 50
    assert custom.epub_cache_mb == 100
