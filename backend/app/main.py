"""HTTP API for the Flutter app: GET /health, /search, /sources, /publications. No accounts, no personal data.

Run: uvicorn app.main:create_app --factory --port 8000
"""
from typing import Optional

import anyio
from anyio import to_thread
from fastapi import FastAPI, HTTPException, Path, Query
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from pydantic import ValidationError

from app.config import Settings, build_http_client, build_publication_store, build_search_service
from app.models import SearchQuery
from app.publications import (MAX_GUTENBERG_ID, PublicationNotFound, PublicationTimeout,
                              PublicationUnavailable)
from app.search import SearchResponse, SkippedSource
from app.sources_info import SOURCES, SourceInfo


# Book files come from third parties: opened directly, they must not run scripts on the API's origin.
# Readium builds its own documents from the fetched text, where this header does not reach, so book pages are also
# served without scripts (app/sanitize.py).
GZIP_MINIMUM_BYTES = 1000
GZIP_LEVEL = 6   # 9 costs twice the CPU for a few percent
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
    # A search with a few audiobooks is 100 KB of repetitive JSON; gzip makes it about a tenth. Only for
    # clients that ask (browsers and Dart's http always do). Images and other compressed files are skipped.
    app.add_middleware(GZipMiddleware, minimum_size=GZIP_MINIMUM_BYTES, compresslevel=GZIP_LEVEL)

    @app.get("/health")
    def health() -> dict:
        return {"status": "ok"}

    # Created on first use, inside the running event loop. Searches wait here (as cheap coroutines) when
    # max_concurrent_searches are running, instead of each holding a worker thread of the default pool.
    # Two limiters of one size: admission is waited for (briefly), the worker threads then never are.
    search_limiter: list[anyio.CapacityLimiter] = []

    @app.get("/search", response_model=SearchResponse)
    async def search(
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
        if not search_limiter:
            slots = max(1, settings.max_concurrent_searches)
            search_limiter.extend([anyio.CapacityLimiter(slots), anyio.CapacityLimiter(slots)])
        admission, workers = search_limiter
        with anyio.move_on_after(settings.search_admission_seconds) as wait:
            await admission.acquire()
        if wait.cancelled_caught:
            ids = sorted(query.sources if query.sources is not None else (s.id for s in SOURCES))
            return SearchResponse(works=[], unavailable_sources=ids,
                                  skipped=[SkippedSource(source=i, reason="busy") for i in ids])
        try:
            return await to_thread.run_sync(search_service.search, query, limiter=workers)
        finally:
            admission.release()

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
