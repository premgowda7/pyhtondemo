from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app


def test_index_renders_with_security_headers():
    client = TestClient(create_app(Settings(environment="dev")))
    r = client.get("/")
    assert r.status_code == 200
    assert 'data-api="/api"' in r.text and ">dev<" in r.text
    assert r.headers["X-Frame-Options"] == "DENY"
    assert "default-src 'self'" in r.headers["Content-Security-Policy"]


def test_static_and_probes():
    client = TestClient(create_app())
    assert client.get("/static/app.js").status_code == 200
    assert client.get("/healthz").json() == {"status": "ok"}
    assert "web_page_views_total" in client.get("/metrics").text
