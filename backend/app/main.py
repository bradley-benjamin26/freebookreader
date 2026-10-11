"""HTTP API for the Flutter app: GET /health, /search, /sources, /publications. No accounts, no personal data.

Run: uvicorn app.main:create_app --factory --port 8000
"""
from typing import Optional

from fastapi import FastAPI, HTTPException, Path, Query
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, Response
from fastapi.middleware.cors import CORSMiddleware
from pydantic import ValidationError

from app.config import Settings, build_http_client, build_publication_store, build_search_service
from app.models import SearchQuery
from app.publications import (MAX_GUTENBERG_ID, PublicationNotFound, PublicationTimeout,
                              PublicationUnavailable)
from app.search import SearchResponse
from app.sources_info import SOURCES, SourceInfo


# Book files come from third parties: opened directly, they must not run scripts on the API's origin.
# Readium builds its own documents from the fetched text, so this does not affect the reader.
BOOK_FILE_HEADERS = {"Content-Security-Policy": "sandbox", "X-Content-Type-Options": "nosniff",
                     "Cache-Control": "public, max-age=86400"}


def create_app(search_service=None, settings: Settings | None = None, publication_store=None) -> FastAPI:
    settings = settings or Settings.from_env()
    client = None
    if search_service is None or publication_store is None:
        client = build_http_client(settings)
    if search_service is None:
        search_service = build_search_service(settings, client)
    if publication_store is None:
        publication_store = build_publication_store(settings, client)

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

    book_id_path = Path(ge=1, le=MAX_GUTENBERG_ID)

    @app.get("/publications/gutenberg/{book_id}/manifest.json")
    def publication_manifest(book_id: int = book_id_path) -> Response:
        manifest = _publication_call(publication_store.manifest, book_id)
        return JSONResponse(manifest, media_type="application/webpub+json",
                            headers={"X-Content-Type-Options": "nosniff"})

    @app.get("/publications/gutenberg/{book_id}/{href:path}")
    def publication_resource(href: str, book_id: int = book_id_path) -> Response:
        data, media_type = _publication_call(publication_store.resource, book_id, href)
        return Response(data, media_type=media_type, headers=BOOK_FILE_HEADERS)

    return app


def _publication_call(method, *args):
    try:
        return method(*args)
    except PublicationNotFound as error:
        raise HTTPException(404, "Not found") from error
    except PublicationTimeout as error:
        raise HTTPException(504, "Project Gutenberg did not answer in time") from error
    except PublicationUnavailable as error:
        raise HTTPException(502, "The book could not be loaded from Project Gutenberg") from error
