"""Tests unitarios para la aplicación Flask."""

import pytest
from app import app


@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as client:
        yield client


def test_index(client):
    """Test endpoint raíz."""
    resp = client.get("/")
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["status"] == "running"
    assert "version" in data


def test_health(client):
    """Test health check."""
    resp = client.get("/health")
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["status"] == "healthy"
    assert "uptime_seconds" in data


def test_readiness(client):
    """Test readiness check."""
    resp = client.get("/ready")
    assert resp.status_code == 200
    assert resp.get_json()["status"] == "ready"


def test_get_items(client):
    """Test obtener lista de items."""
    resp = client.get("/api/items")
    assert resp.status_code == 200
    data = resp.get_json()
    assert "items" in data
    assert data["total"] > 0


def test_create_item_success(client):
    """Test crear item exitosamente."""
    resp = client.post(
        "/api/items",
        json={"name": "Test Item", "category": "test"},
        content_type="application/json",
    )
    assert resp.status_code == 201
    assert resp.get_json()["message"] == "Item creado"


def test_create_item_missing_name(client):
    """Test crear item sin nombre - debe fallar."""
    resp = client.post(
        "/api/items",
        json={"category": "test"},
        content_type="application/json",
    )
    assert resp.status_code == 400
    assert "error" in resp.get_json()


def test_simulate_error(client):
    """Test endpoint de error simulado."""
    resp = client.get("/api/simulate/error")
    assert resp.status_code == 500


def test_metrics(client):
    """Test endpoint de métricas Prometheus."""
    resp = client.get("/metrics")
    assert resp.status_code == 200
    assert b"app_request_total" in resp.data
