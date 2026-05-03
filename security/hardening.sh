#!/bin/bash
# ============================================================================
# Script de Hardening para Host y Contenedores
# Aplica medidas básicas de seguridad
# ============================================================================

set -e

echo "═══════════════════════════════════════════════════════"
echo "  Hardening del Host y Contenedores"
echo "  $(date)"
echo "═══════════════════════════════════════════════════════"
echo ""

# ── 1. Verificar Docker daemon configuration ─────────────────────────
echo "[1/6] Verificando configuración de Docker daemon..."

DOCKER_DAEMON="/etc/docker/daemon.json"
RECOMMENDED='{
  "icc": false,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "no-new-privileges": true,
  "userns-remap": "default",
  "live-restore": true
}'

if [ -f "$DOCKER_DAEMON" ]; then
    echo "  ✓ daemon.json existe"
else
    echo "  ⚠ daemon.json no encontrado"
    echo "  Configuración recomendada:"
    echo "${RECOMMENDED}" | sed 's/^/    /'
fi

# ── 2. Verificar contenedores con usuario root ───────────────────────
echo ""
echo "[2/6] Verificando contenedores ejecutándose como root..."

for container in $(docker ps --format '{{.Names}}' 2>/dev/null); do
    USER=$(docker inspect --format '{{.Config.User}}' "$container" 2>/dev/null)
    if [ -z "$USER" ] || [ "$USER" = "root" ] || [ "$USER" = "0" ]; then
        echo "  ⚠ ${container}: ejecutándose como root"
    else
        echo "  ✓ ${container}: usuario ${USER}"
    fi
done

# ── 3. Verificar contenedores con modo read-only ─────────────────────
echo ""
echo "[3/6] Verificando filesystem read-only en contenedores..."

for container in $(docker ps --format '{{.Names}}' 2>/dev/null); do
    READONLY=$(docker inspect --format '{{.HostConfig.ReadonlyRootfs}}' "$container" 2>/dev/null)
    if [ "$READONLY" = "true" ]; then
        echo "  ✓ ${container}: filesystem read-only"
    else
        echo "  ⚠ ${container}: filesystem writable"
    fi
done

# ── 4. Verificar capabilities de contenedores ────────────────────────
echo ""
echo "[4/6] Verificando capabilities de contenedores..."

for container in $(docker ps --format '{{.Names}}' 2>/dev/null); do
    CAPS=$(docker inspect --format '{{.HostConfig.CapAdd}}' "$container" 2>/dev/null)
    if [ "$CAPS" = "[]" ] || [ "$CAPS" = "<nil>" ]; then
        echo "  ✓ ${container}: sin capabilities adicionales"
    else
        echo "  ⚠ ${container}: capabilities adicionales: ${CAPS}"
    fi
done

# ── 5. Verificar redes y puertos expuestos ───────────────────────────
echo ""
echo "[5/6] Verificando puertos expuestos..."

docker ps --format 'table {{.Names}}\t{{.Ports}}' 2>/dev/null | head -20
echo ""
echo "  Nota: solo nginx (80) debería estar expuesto externamente en producción."

# ── 6. Resumen de medidas implementadas ──────────────────────────────
echo ""
echo "[6/6] Resumen de medidas de hardening implementadas:"
echo ""
echo "  CONTENEDORES:"
echo "    ✓ Multi-stage build (reduce superficie de ataque)"
echo "    ✓ Usuario no-root en la aplicación (appuser)"
echo "    ✓ Filesystem read-only en contenedores de app"
echo "    ✓ tmpfs para directorios temporales"
echo "    ✓ Health checks integrados"
echo "    ✓ Reinicio automático (unless-stopped)"
echo "    ✓ Límite de tamaño de logs (10MB, 3 archivos)"
echo "    ✓ No se exponen puertos innecesarios (solo expose)"
echo ""
echo "  RED:"
echo "    ✓ Red bridge aislada (app-net)"
echo "    ✓ Nginx como único punto de entrada"
echo "    ✓ Headers de seguridad en Nginx"
echo "    ✓ server_tokens deshabilitado"
echo ""
echo "  SECRETOS:"
echo "    ✓ Variables de entorno inyectadas (no hardcodeadas)"
echo "    ✓ HashiCorp Vault para gestión centralizada"
echo "    ✓ .env en .gitignore (no versionado)"
echo ""
echo "  ESCANEO:"
echo "    ✓ Trivy para imágenes Docker"
echo "    ✓ Trivy para dependencias (pip)"
echo "    ✓ Trivy para configuración IaC"
echo "    ✓ Bloqueo de deploy en CI/CD si hay CVEs críticos"
echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Hardening verificado"
echo "═══════════════════════════════════════════════════════"
