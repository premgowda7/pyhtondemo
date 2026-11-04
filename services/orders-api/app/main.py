import logging
import time
from collections.abc import Iterator
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, HTTPException, Query, Request, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest
from sqlalchemy import select, text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session, sessionmaker

from .config import Settings
from .db import Base, build_engine
from .logging_config import configure_logging
from .models import Order
from .schemas import OrderCreate, OrderOut

logger = logging.getLogger("orders_api")

ORDERS_CREATED = Counter("orders_created_total", "Orders accepted by the API")
REQUEST_LATENCY = Histogram("http_request_duration_seconds", "HTTP request latency", ["method", "route", "status"])


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or Settings()
    configure_logging("orders-api", settings.log_level)
    engine = build_engine(settings)
    session_factory = sessionmaker(bind=engine, expire_on_commit=False)

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        # Demo only: production schemas should be managed by migrations (Alembic) in a Job.
        Base.metadata.create_all(engine)
        logger.info("orders-api started")
        yield
        engine.dispose()

    app = FastAPI(title="orders-api", version="1.0.0", lifespan=lifespan)

    def get_db() -> Iterator[Session]:
        db = session_factory()
        try:
            yield db
        finally:
            db.close()

    @app.middleware("http")
    async def observe(request: Request, call_next):
        start = time.perf_counter()
        response = await call_next(request)
        route = request.scope.get("route")
        REQUEST_LATENCY.labels(request.method, getattr(route, "path", "unmatched"), str(response.status_code)).observe(
            time.perf_counter() - start
        )
        return response

    @app.get("/healthz", include_in_schema=False)
    def healthz() -> dict:
        """Liveness: the process is up. Never checks dependencies (avoids restart storms)."""
        return {"status": "ok"}

    @app.get("/readyz", include_in_schema=False)
    def readyz(db: Session = Depends(get_db)) -> dict:
        """Readiness: can we serve traffic? Pulls the pod out of the Service if the DB is unreachable."""
        try:
            db.execute(text("SELECT 1"))
        except SQLAlchemyError:
            logger.exception("readiness check failed: database unreachable")
            raise HTTPException(status_code=503, detail="database unavailable") from None
        return {"status": "ready"}

    @app.get("/metrics", include_in_schema=False)
    def metrics() -> Response:
        return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)

    @app.post("/api/orders", status_code=201, response_model=OrderOut)
    def create_order(payload: OrderCreate, db: Session = Depends(get_db)) -> Order:
        order = Order(item=payload.item, quantity=payload.quantity, status="PENDING")
        db.add(order)
        db.commit()
        db.refresh(order)
        ORDERS_CREATED.inc()
        logger.info("order created", extra={"order_id": order.id})
        return order

    @app.get("/api/orders", response_model=list[OrderOut])
    def list_orders(limit: int = Query(20, ge=1, le=100), db: Session = Depends(get_db)):
        return db.scalars(select(Order).order_by(Order.id.desc()).limit(limit)).all()

    @app.get("/api/orders/{order_id}", response_model=OrderOut)
    def get_order(order_id: int, db: Session = Depends(get_db)) -> Order:
        order = db.get(Order, order_id)
        if order is None:
            raise HTTPException(status_code=404, detail="order not found")
        return order

    return app
