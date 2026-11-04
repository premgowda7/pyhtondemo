import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Response
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import sessionmaker

from .config import Settings
from .db import build_engine
from .logging_config import configure_logging
from .processor import Processor

logger = logging.getLogger("worker")


def create_app(settings: Settings | None = None) -> FastAPI:
    """The worker has no public API; HTTP is only for probes and metrics."""
    settings = settings or Settings()
    configure_logging("worker", settings.log_level)
    engine = build_engine(settings)
    session_factory = sessionmaker(bind=engine, expire_on_commit=False)
    processor = Processor(session_factory, settings.poll_interval_seconds, settings.batch_size)

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        processor.start()
        logger.info("worker started")
        yield
        processor.stop()  # SIGTERM -> finish current batch, then exit
        engine.dispose()

    app = FastAPI(title="worker", version="1.0.0", lifespan=lifespan, docs_url=None, redoc_url=None)
    app.state.processor = processor

    @app.get("/healthz")
    def healthz() -> dict:
        stalled_for = processor.seconds_since_heartbeat()
        if stalled_for > settings.stall_threshold_seconds:
            raise HTTPException(status_code=503, detail=f"processing loop stalled for {stalled_for:.0f}s")
        return {"status": "ok"}

    @app.get("/readyz")
    def readyz() -> dict:
        try:
            with engine.connect() as conn:
                conn.execute(text("SELECT 1"))
        except SQLAlchemyError:
            raise HTTPException(status_code=503, detail="database unavailable") from None
        return {"status": "ready"}

    @app.get("/metrics")
    def metrics() -> Response:
        return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)

    return app
