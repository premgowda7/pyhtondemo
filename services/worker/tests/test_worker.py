from sqlalchemy import create_engine, select
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.db import Base
from app.models import Order
from app.processor import Processor, process_batch


def make_session_factory():
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    Base.metadata.create_all(engine)
    return sessionmaker(bind=engine, expire_on_commit=False)


def seed(factory, n, status="PENDING"):
    with factory.begin() as db:
        db.add_all(Order(item=f"item-{i}", quantity=1, status=status) for i in range(n))


def test_processes_pending_in_batches():
    factory = make_session_factory()
    seed(factory, 5)
    seed(factory, 2, status="PROCESSED")
    assert process_batch(factory, batch_size=3) == 3
    assert process_batch(factory, batch_size=3) == 2
    assert process_batch(factory, batch_size=3) == 0
    with factory() as db:
        orders = db.scalars(select(Order)).all()
        assert all(o.status == "PROCESSED" for o in orders)
        assert sum(o.processed_at is not None for o in orders) == 5


def test_heartbeat_advances_and_stops_cleanly():
    factory = make_session_factory()
    p = Processor(factory, interval=0.05, batch_size=10)
    p.last_heartbeat -= 100
    p.start()
    p.stop_event.wait(0.2)
    assert p.seconds_since_heartbeat() < 1
    p.stop()
    assert not p.thread.is_alive()


def test_health_endpoint_reports_stall(monkeypatch):
    from fastapi.testclient import TestClient

    from app.config import Settings
    from app.main import create_app

    app = create_app(Settings(database_url="sqlite://", stall_threshold_seconds=30))
    with TestClient(app) as client:
        assert client.get("/healthz").status_code == 200
        monkeypatch.setattr(app.state.processor, "seconds_since_heartbeat", lambda: 120)
        assert client.get("/healthz").status_code == 503
