# Documentación de Seguridad (DevSecOps)

## 1. Gestión de Secretos

### HashiCorp Vault

Se utiliza HashiCorp Vault como almacén centralizado de secretos. En el entorno de desarrollo se ejecuta en modo `dev`, que proporciona un servidor en memoria con un token raíz conocido. En un entorno de producción real se configuraría con backend de almacenamiento persistente, auto-unseal y políticas granulares de acceso.

**Secretos almacenados:**
- `APP_SECRET_KEY` — Clave secreta de Flask para firmar sesiones
- `DB_PASSWORD` — Contraseña de base de datos
- `GRAFANA_ADMIN_PASSWORD` — Contraseña del admin de Grafana

**Flujo de secretos:**
1. Los secretos se almacenan en Vault (`vault/init-vault.sh`)
2. Se recuperan y se inyectan como variables de entorno
3. La aplicación los lee con `os.environ.get()`
4. Nunca se hardcodean en código ni en archivos de configuración versionados

### Protección de Credenciales en Repositorio

- El archivo `.env` está en `.gitignore` y nunca se commitea
- Se proporciona `.env.example` como referencia con valores placeholder
- Los secretos en el pipeline CI/CD se manejan con GitHub Secrets

## 2. Escaneo de Vulnerabilidades

### Trivy

Se ejecutan 3 tipos de escaneo:

**Escaneo de imagen Docker:** Analiza la imagen construida en busca de vulnerabilidades conocidas (CVEs) en paquetes del sistema operativo y librerías instaladas. Se enfoca en severidad HIGH y CRITICAL.

**Escaneo de dependencias (filesystem):** Analiza `requirements.txt` y los paquetes Python instalados en busca de vulnerabilidades conocidas en dependencias.

**Escaneo de configuración IaC:** Analiza el Dockerfile y docker-compose.yml en busca de malas prácticas de configuración como contenedores ejecutándose como root, puertos innecesariamente expuestos o falta de health checks.

### Ejecución Local

```bash
chmod +x security/trivy-scan.sh
./security/trivy-scan.sh
```

Los reportes se generan en `security/reports/` con timestamp.

## 3. Integración en CI/CD

El pipeline de GitHub Actions incluye un stage dedicado de seguridad (`security-scan`) que:

1. Construye la imagen Docker
2. Ejecuta Trivy contra la imagen (HIGH + CRITICAL, informativo)
3. Ejecuta Trivy contra las dependencias (HIGH + CRITICAL, informativo)
4. Ejecuta Trivy contra la configuración IaC (HIGH + CRITICAL, informativo)
5. Ejecuta un gate de seguridad: si hay vulnerabilidades **CRITICAL**, el pipeline falla y el deploy se **bloquea**

Los reportes de escaneo se suben como artifacts del workflow para revisión posterior.

## 4. Hardening

### Contenedores

**Multi-stage build:** La imagen final solo contiene el runtime de Python y la aplicación, sin herramientas de compilación ni archivos innecesarios. Esto reduce la superficie de ataque.

**Usuario no-root:** La aplicación se ejecuta con el usuario `appuser` (UID no privilegiado). Si un atacante compromete la aplicación, no tiene permisos de root dentro del contenedor.

**Filesystem read-only:** Los contenedores de la aplicación tienen `read_only: true`, lo que impide la escritura en el filesystem del contenedor. Solo `/tmp` (montado como tmpfs) permite escritura temporal.

**Health checks:** Docker verifica periódicamente que la aplicación responde. Si falla 3 veces consecutivas, el contenedor se marca como unhealthy y se reinicia.

### Red

**Red aislada:** Todos los servicios están en una red bridge dedicada (`app-net`). No comparten la red bridge por defecto de Docker.

**Punto de entrada único:** Solo Nginx expone puertos al host (puerto 80). Los servicios internos usan `expose` en lugar de `ports`, haciéndolos accesibles solo dentro de la red Docker.

**Headers de seguridad en Nginx:**
- `X-Content-Type-Options: nosniff` — Previene MIME sniffing
- `X-Frame-Options: SAMEORIGIN` — Previene clickjacking
- `X-XSS-Protection: 1; mode=block` — Activa filtro XSS del navegador
- `Referrer-Policy: strict-origin-when-cross-origin` — Limita información del referrer
- `server_tokens off` — Nginx no revela su versión

### Logs

Los logs de Docker están limitados a 10 MB por archivo con máximo 3 archivos. Esto previene que un servicio que genere logs excesivos llene el disco del host.

## 5. Verificación de Hardening

```bash
chmod +x security/hardening.sh
./security/hardening.sh
```

Este script verifica automáticamente: usuarios de contenedores, filesystem read-only, capabilities adicionales y puertos expuestos.
