import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.db import read_password
from app.main import create_app


@pytest.fixture()
def client():
    app = create_app(Settings(database_url="sqlite://"))
    with TestClient(app) as c:  # `with` runs the lifespan (creates tables)
        yield c


def test_health_and_ready(client):
    assert client.get("/healthz").json() == {"status": "ok"}
    assert client.get("/readyz").status_code == 200


def test_create_get_list_order(client):
    r = client.post("/api/orders", json={"item": "laptop", "quantity": 2})
    assert r.status_code == 201
    order = r.json()
    assert order["status"] == "PENDING" and order["item"] == "laptop"

    assert client.get(f"/api/orders/{order['id']}").json()["quantity"] == 2
    assert [o["id"] for o in client.get("/api/orders").json()] == [order["id"]]


@pytest.mark.parametrize("body", [{"item": "", "quantity": 1}, {"item": "x", "quantity": 0}, {"item": "x"}])
def test_validation(client, body):
    assert client.post("/api/orders", json=body).status_code == 422


def test_not_found(client):
    assert client.get("/api/orders/999").status_code == 404


def test_metrics_exposed(client):
    client.post("/api/orders", json={"item": "pen", "quantity": 1})
    body = client.get("/metrics").text
    assert "orders_created_total" in body and "http_request_duration_seconds" in body


def test_password_read_from_csi_file(tmp_path):
    f = tmp_path / "db-password"
    f.write_text("s3cret\n")
    assert read_password(Settings(db_password_file=str(f))) == "s3cret"
