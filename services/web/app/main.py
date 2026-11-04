from pathlib import Path

from fastapi import FastAPI, Request, Response
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from prometheus_client import CONTENT_TYPE_LATEST, Counter, generate_latest

from .config import Settings
from .logging_config import configure_logging

BASE = Path(__file__).parent
PAGE_VIEWS = Counter("web_page_views_total", "Index page views")

SECURITY_HEADERS = {
    "Content-Security-Policy": "default-src 'self'; frame-ancestors 'none'",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "no-referrer",
}


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or Settings()
    configure_logging("web", settings.log_level)
    app = FastAPI(title="web", docs_url=None, redoc_url=None, openapi_url=None)
    templates = Jinja2Templates(directory=BASE / "templates")
    app.mount("/static", StaticFiles(directory=BASE / "static"), name="static")

    @app.middleware("http")
    async def security_headers(request: Request, call_next):
        response = await call_next(request)
        response.headers.update(SECURITY_HEADERS)
        return response

    @app.get("/", response_class=HTMLResponse)
    def index(request: Request):
        PAGE_VIEWS.inc()
        return templates.TemplateResponse(
            request,
            "index.html",
            {"title": settings.app_title, "env": settings.environment, "api": settings.api_base_path},
        )

    @app.get("/healthz")
    def healthz() -> dict:
        return {"status": "ok"}

    @app.get("/readyz")
    def readyz() -> dict:
        return {"status": "ready"}

    @app.get("/metrics")
    def metrics() -> Response:
        return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)

    return app
