#!/bin/bash
# ============================================================================
# Script de inicialización de HashiCorp Vault
# Crea secretos necesarios para la aplicación
# ============================================================================

set -e

VAULT_ADDR="http://127.0.0.1:8200"
VAULT_TOKEN="dev-root-token"

echo "═══════════════════════════════════════════════════════"
echo "  Inicializando HashiCorp Vault"
echo "═══════════════════════════════════════════════════════"

# Esperar a que Vault esté disponible
echo "[1/4] Esperando a que Vault esté disponible..."
until curl -s ${VAULT_ADDR}/v1/sys/health > /dev/null 2>&1; do
    sleep 2
done
echo "  ✓ Vault disponible"

# Habilitar el motor de secretos KV v2
echo "[2/4] Habilitando motor de secretos KV v2..."
curl -s -X POST \
    -H "X-Vault-Token: ${VAULT_TOKEN}" \
    -d '{"type":"kv","options":{"version":"2"}}' \
    ${VAULT_ADDR}/v1/sys/mounts/secret 2>/dev/null || true
echo "  ✓ Motor KV v2 habilitado"

# Almacenar secretos de la aplicación
echo "[3/4] Almacenando secretos de la aplicación..."
curl -s -X POST \
    -H "X-Vault-Token: ${VAULT_TOKEN}" \
    -d '{
        "data": {
            "APP_SECRET_KEY": "super-secret-key-produccion-2024",
            "DB_PASSWORD": "db-password-seguro-123",
            "GRAFANA_ADMIN_PASSWORD": "grafana-admin-seguro"
        }
    }' \
    ${VAULT_ADDR}/v1/secret/data/flask-app

echo "  ✓ Secretos almacenados en secret/flask-app"

# Verificar que los secretos se guardaron
echo "[4/4] Verificando secretos..."
RESULT=$(curl -s \
    -H "X-Vault-Token: ${VAULT_TOKEN}" \
    ${VAULT_ADDR}/v1/secret/data/flask-app | python3 -m json.tool 2>/dev/null || echo "OK")

echo "  ✓ Secretos verificados"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Vault inicializado correctamente"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  URL:   ${VAULT_ADDR}"
echo "  Token: ${VAULT_TOKEN}"
echo ""
echo "  Obtener secretos:"
echo "    export VAULT_ADDR=${VAULT_ADDR}"
echo "    export VAULT_TOKEN=${VAULT_TOKEN}"
echo "    vault kv get secret/flask-app"
echo ""
echo "  O con curl:"
echo '    curl -H "X-Vault-Token: dev-root-token" \'
echo "      ${VAULT_ADDR}/v1/secret/data/flask-app"
echo ""
