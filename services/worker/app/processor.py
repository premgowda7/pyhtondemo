import logging
import threading
import time
from datetime import UTC, datetime

from prometheus_client import Counter
from sqlalchemy import select
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import sessionmaker

from .models import Order

logger = logging.getLogger("worker")

ORDERS_PROCESSED = Counter("orders_processed_total", "Orders processed by the worker")
BATCH_ERRORS = Counter("worker_batch_errors_total", "Failed processing batches")


def process_batch(session_factory: sessionmaker, batch_size: int) -> int:
    """Claim and process up to `batch_size` pending orders in one transaction.

    FOR UPDATE SKIP LOCKED lets several worker replicas run in parallel without
    processing the same order twice (no external queue needed for this demo).
    """
    with session_factory.begin() as db:
        orders = db.scalars(
            select(Order)
            .where(Order.status == "PENDING")
            .order_by(Order.id)
            .limit(batch_size)
            .with_for_update(skip_locked=True)
        ).all()
        now = datetime.now(UTC)
        for order in orders:
            # Real business logic (payment, inventory, ...) would go here.
            order.status = "PROCESSED"
            order.processed_at = now
        return len(orders)


class Processor:
    def __init__(self, session_factory: sessionmaker, interval: float, batch_size: int) -> None:
        self.session_factory = session_factory
        self.interval = interval
        self.batch_size = batch_size
        self.stop_event = threading.Event()
        self.last_heartbeat = time.monotonic()
        self.thread = threading.Thread(target=self._run, name="processor", daemon=True)

    def start(self) -> None:
        self.thread.start()

    def stop(self, timeout: float = 10.0) -> None:
        self.stop_event.set()
        self.thread.join(timeout)

    def seconds_since_heartbeat(self) -> float:
        return time.monotonic() - self.last_heartbeat

    def _run(self) -> None:
        while not self.stop_event.is_set():
            processed = 0
            try:
                processed = process_batch(self.session_factory, self.batch_size)
                if processed:
                    ORDERS_PROCESSED.inc(processed)
                    logger.info("processed orders", extra={"count": processed})
            except SQLAlchemyError:
                BATCH_ERRORS.inc()
                logger.exception("batch failed; will retry")
            # Heartbeat proves the loop is alive even while the DB is down
            # (DB outages are a readiness concern, not a liveness one).
            self.last_heartbeat = time.monotonic()
            # Full batch -> more work is probably waiting, loop immediately.
            self.stop_event.wait(0 if processed == self.batch_size else self.interval)
