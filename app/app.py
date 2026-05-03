"""
Aplicación Flask con observabilidad integrada.
- Métricas Prometheus via prometheus_flask_instrumentator
- Logs estructurados JSON para ELK
- Health checks para Docker/balanceador
- Gestión de secretos via variables de entorno (inyectadas por Vault)
"""

import os
import time
import logging
import json
import random
from datetime import datetime, timezone

from flask import Flask, jsonify, request, g
from prometheus_client import (
    Counter, Histogram, Gauge,
    generate_latest, CONTENT_TYPE_LATEST,
)

# ── Logging estructurado JSON ────────────────────────────────────────
class JSONFormatter(logging.Formatter):
    def format(self, record):
        log_entry = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "module": record.module,
            "function": record.funcName,
            "line": record.lineno,
            "service": "flask-app",
            "hostname": os.environ.get("HOSTNAME", "unknown"),
        }
        if record.exc_info and record.exc_info[0]:
            log_entry["exception"] = self.formatException(record.exc_info)
        return json.dumps(log_entry)

handler = logging.StreamHandler()
handler.setFormatter(JSONFormatter())
logging.root.handlers = [handler]
logging.root.setLevel(logging.INFO)

logger = logging.getLogger("app")

# ── Métricas Prometheus ──────────────────────────────────────────────
REQUEST_COUNT = Counter(
    "app_request_total",
    "Total de requests",
    ["method", "endpoint", "status"],
)
REQUEST_LATENCY = Histogram(
    "app_request_duration_seconds",
    "Latencia de requests en segundos",
    ["method", "endpoint"],
    buckets=[0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5],
)
ACTIVE_REQUESTS = Gauge(
    "app_active_requests",
    "Requests activos en este momento",
)
APP_INFO = Gauge(
    "app_info",
    "Información de la aplicación",
    ["version", "hostname"],
)

VERSION = os.environ.get("APP_VERSION", "1.0.0")
APP_INFO.labels(
    version=VERSION,
    hostname=os.environ.get("HOSTNAME", "unknown"),
).set(1)

# ── Flask App ────────────────────────────────────────────────────────
app = Flask(__name__)

# Secreto inyectado por Vault / variable de entorno
app.config["SECRET_KEY"] = os.environ.get("APP_SECRET_KEY", "dev-secret-insecure")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "not-set")

START_TIME = time.time()


@app.before_request
def before_request():
    g.start_time = time.time()
    ACTIVE_REQUESTS.inc()


@app.after_request
def after_request(response):
    latency = time.time() - g.start_time
    ACTIVE_REQUESTS.dec()
    REQUEST_COUNT.labels(
        method=request.method,
        endpoint=request.path,
        status=response.status_code,
    ).inc()
    REQUEST_LATENCY.labels(
        method=request.method,
        endpoint=request.path,
    ).observe(latency)
    logger.info(
        "request",
        extra={
            "method": request.method,
            "path": request.path,
            "status": response.status_code,
            "latency_ms": round(latency * 1000, 2),
            "remote_addr": request.remote_addr,
        },
    )
    return response


# ── Endpoints ────────────────────────────────────────────────────────

@app.route("/")
def index():
    return jsonify({
        "service": "Proyecto Final - Plataforma DevOps",
        "version": VERSION,
        "hostname": os.environ.get("HOSTNAME", "unknown"),
        "status": "running",
    })


@app.route("/health")
def health():
    """Health check para Docker y balanceador de carga."""
    return jsonify({"status": "healthy", "uptime_seconds": round(time.time() - START_TIME, 1)})


@app.route("/ready")
def readiness():
    """Readiness check - verifica que la app puede atender tráfico."""
    # Aquí se verificaría conexión a DB, cache, etc.
    return jsonify({"status": "ready"})


@app.route("/api/items", methods=["GET"])
def get_items():
    """Endpoint de ejemplo - lista de items."""
    items = [
        {"id": 1, "name": "Servidor Dell R750", "category": "hardware"},
        {"id": 2, "name": "Switch FortiGate 80F", "category": "network"},
        {"id": 3, "name": "Licencia Windows Server", "category": "software"},
        {"id": 4, "name": "UPS APC 3000VA", "category": "power"},
    ]
    logger.info(f"Retornando {len(items)} items")
    return jsonify({"items": items, "total": len(items)})


@app.route("/api/items", methods=["POST"])
def create_item():
    """Endpoint de ejemplo - crear item."""
    data = request.get_json(silent=True)
    if not data or "name" not in data:
        logger.warning("Intento de crear item sin nombre")
        return jsonify({"error": "Campo 'name' es requerido"}), 400
    logger.info(f"Item creado: {data['name']}")
    return jsonify({"message": "Item creado", "item": data}), 201


@app.route("/api/simulate/error")
def simulate_error():
    """Simula un error 500 para pruebas de alertas."""
    logger.error("Error simulado para pruebas de observabilidad")
    return jsonify({"error": "Error interno simulado"}), 500


@app.route("/api/simulate/slow")
def simulate_slow():
    """Simula latencia alta para pruebas de métricas."""
    delay = random.uniform(1.0, 3.0)
    logger.warning(f"Request lento simulado: {delay:.2f}s")
    time.sleep(delay)
    return jsonify({"message": "Respuesta lenta", "delay_seconds": round(delay, 2)})


@app.route("/metrics")
def metrics():
    """Endpoint de métricas Prometheus."""
    return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}


# ── Main ─────────────────────────────────────────────────────────────
if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    logger.info(f"Iniciando aplicación v{VERSION} en puerto {port}")
    app.run(host="0.0.0.0", port=port, debug=False)
