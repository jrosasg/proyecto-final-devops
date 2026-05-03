# ── Stage 1: Builder ─────────────────────────────────────────────────
FROM python:3.12-slim AS builder

WORKDIR /build

COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ── Stage 2: Production ─────────────────────────────────────────────
FROM python:3.12-slim AS production

# Hardening: crear usuario no-root
RUN groupadd -r appuser && useradd -r -g appuser -d /app -s /sbin/nologin appuser

# Hardening: instalar solo lo necesario, limpiar cache
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copiar dependencias del builder
COPY --from=builder /install /usr/local

# Copiar código de la aplicación
COPY app.py .

# Hardening: cambiar ownership y permisos
RUN chown -R appuser:appuser /app && \
    chmod -R 550 /app

# Hardening: filesystem de solo lectura donde sea posible
# (se configura en docker-compose con read_only: true)

# Usar usuario no-root
USER appuser

# Variables de entorno por defecto
ENV PORT=5000 \
    APP_VERSION=1.0.0 \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

EXPOSE ${PORT}

# Health check integrado
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:${PORT}/health || exit 1

# Usar gunicorn en producción (4 workers)
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--access-logfile", "-", "app:app"]
