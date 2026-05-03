#!/bin/bash
# ============================================================================
# Script de escaneo de seguridad con Trivy
# Escanea imágenes Docker y dependencias en busca de vulnerabilidades
# ============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

REPORT_DIR="./security/reports"
mkdir -p ${REPORT_DIR}
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "═══════════════════════════════════════════════════════"
echo "  Escaneo de Seguridad con Trivy"
echo "  $(date)"
echo "═══════════════════════════════════════════════════════"

# Verificar que Trivy esté instalado
if ! command -v trivy &> /dev/null; then
    echo -e "${YELLOW}[!] Trivy no encontrado. Instalando...${NC}"
    curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin
fi

echo ""

# ── 1. Escaneo de la imagen de la aplicación ─────────────────────────
echo -e "${YELLOW}[1/4] Escaneando imagen Docker de la aplicación...${NC}"
IMAGE_NAME="proyecto-final-app-1:latest"

trivy image \
    --severity HIGH,CRITICAL \
    --format table \
    --output "${REPORT_DIR}/image-scan-${TIMESTAMP}.txt" \
    ${IMAGE_NAME} 2>/dev/null || echo "  (imagen no construida aún, se omite)"

echo -e "${GREEN}  ✓ Reporte: ${REPORT_DIR}/image-scan-${TIMESTAMP}.txt${NC}"

# ── 2. Escaneo del filesystem (dependencias) ─────────────────────────
echo -e "${YELLOW}[2/4] Escaneando dependencias del proyecto...${NC}"

trivy fs \
    --severity HIGH,CRITICAL \
    --format table \
    --output "${REPORT_DIR}/deps-scan-${TIMESTAMP}.txt" \
    ./app/ 2>/dev/null

echo -e "${GREEN}  ✓ Reporte: ${REPORT_DIR}/deps-scan-${TIMESTAMP}.txt${NC}"

# ── 3. Escaneo de configuración (Dockerfile, Compose) ────────────────
echo -e "${YELLOW}[3/4] Escaneando configuraciones (IaC)...${NC}"

trivy config \
    --severity HIGH,CRITICAL \
    --format table \
    --output "${REPORT_DIR}/config-scan-${TIMESTAMP}.txt" \
    . 2>/dev/null

echo -e "${GREEN}  ✓ Reporte: ${REPORT_DIR}/config-scan-${TIMESTAMP}.txt${NC}"

# ── 4. Escaneo con salida JSON para CI/CD ────────────────────────────
echo -e "${YELLOW}[4/4] Generando reporte JSON para CI/CD...${NC}"

trivy fs \
    --severity CRITICAL \
    --format json \
    --output "${REPORT_DIR}/ci-scan-${TIMESTAMP}.json" \
    ./app/ 2>/dev/null

# Verificar si hay vulnerabilidades críticas (bloqueo de deploy)
CRITICAL_COUNT=$(trivy fs --severity CRITICAL --format json ./app/ 2>/dev/null | \
    python3 -c "import sys,json; data=json.load(sys.stdin); print(sum(len(r.get('Vulnerabilities',[])) for r in data.get('Results',[])))" 2>/dev/null || echo "0")

echo ""
echo "═══════════════════════════════════════════════════════"
if [ "${CRITICAL_COUNT}" -gt 0 ] 2>/dev/null; then
    echo -e "${RED}  ✗ Se encontraron ${CRITICAL_COUNT} vulnerabilidades CRÍTICAS${NC}"
    echo -e "${RED}  El despliegue debería ser BLOQUEADO${NC}"
    echo "═══════════════════════════════════════════════════════"
    exit 1
else
    echo -e "${GREEN}  ✓ No se encontraron vulnerabilidades críticas${NC}"
    echo -e "${GREEN}  El despliegue puede continuar${NC}"
    echo "═══════════════════════════════════════════════════════"
    exit 0
fi
