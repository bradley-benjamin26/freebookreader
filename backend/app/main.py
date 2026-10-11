"""HTTP API for the Flutter app: GET /health, /search, /sources. No accounts, no personal data.

Run: uvicorn app.main:create_app --factory --port 8000
"""
from typing import Optional

from fastapi import FastAPI, Query
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from pydantic import ValidationError

from app.config import Settings, build_http_client, build_search_service
from app.models import SearchQuery
from app.search import SearchResponse
from app.sources_info import SOURCES, SourceInfo


def create_app(search_service=None, settings: Settings | None = None) -> FastAPI:
    settings = settings or Settings.from_env()
    if search_service is None:
        search_service = build_search_service(settings, build_http_client(settings))

    app = FastAPI(title="Free Book Reader API", version="0.1.0")
    app.add_middleware(CORSMiddleware, allow_origins=list(settings.cors_origins),
                       allow_methods=["GET"], allow_headers=["*"])

    @app.get("/health")
    def health() -> dict:
        return {"status": "ok"}

    @app.get("/search", response_model=SearchResponse)
    def search(
        q: Optional[str] = None,
        title: Optional[str] = None,
        author: Optional[str] = None,
        keyword: Optional[str] = None,
        isbn: Optional[str] = None,
        language: Optional[str] = None,
        format: Optional[str] = None,
        sources: Optional[str] = Query(None, description="Comma-separated source ids"),
        page: int = 1,
    ) -> SearchResponse:
        try:
            query = SearchQuery(
                q=q, title=title, author=author, keyword=keyword, isbn=isbn, language=language,
                format=format, page=page,
                sources=[s.strip() for s in sources.split(",") if s.strip()] if sources else None,
            )
        except ValidationError as error:
            raise RequestValidationError(error.errors(include_url=False)) from error
        return search_service.search(query)

    @app.get("/sources", response_model=list[SourceInfo])
    def list_sources() -> list[SourceInfo]:
        return SOURCES

    return app
