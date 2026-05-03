# 🏗️ Plataforma Local de CI/CD, Observabilidad y Seguridad

Infraestructura local completa que implementa una aplicación con pipeline CI/CD, monitoreo, observabilidad, prácticas DevSecOps y operaciones en producción.

## 📋 Tabla de Contenidos

- [Arquitectura](#arquitectura)
- [Requisitos Previos](#requisitos-previos)
- [Inicio Rápido](#inicio-rápido)
- [Servicios y Puertos](#servicios-y-puertos)
- [Observabilidad](#observabilidad)
- [Seguridad (DevSecOps)](#seguridad-devsecops)
- [Operaciones en Producción](#operaciones-en-producción)
- [Pipeline CI/CD](#pipeline-cicd)
- [Pruebas y Verificación](#pruebas-y-verificación)

## Arquitectura

```
                    ┌─────────────┐
                    │   Usuario   │
                    └──────┬──────┘
                           │ :80
                    ┌──────▼──────┐
                    │  Nginx LB   │
                    │ (least_conn)│
                    └──┬───┬───┬──┘
                 ┌─────┘   │   └─────┐
                 ▼         ▼         ▼
            ┌────────┐┌────────┐┌────────┐
            │ App-1  ││ App-2  ││ App-3  │  Flask + Gunicorn
            │ :5000  ││ :5000  ││ :5000  │  (read-only, non-root)
            └───┬────┘└───┬────┘└───┬────┘
                │         │         │
        ┌───────┴─────────┴─────────┴───────┐
        │            Docker Network          │
        └┬──────┬──────┬──────┬──────┬──────┘
         │      │      │      │      │
    ┌────▼─┐┌──▼───┐┌─▼──┐┌─▼───┐┌─▼────┐
    │Prome-││Grafa-││Elas-││Kiba-││Vault │
    │theus ││na    ││tic  ││na   ││      │
    │:9090 ││:3000 ││:9200││:5601││:8200 │
    └──────┘└──────┘└──┬──┘└─────┘└──────┘
                       │
                  ┌────▼────┐
                  │Filebeat │
                  └─────────┘
```

## Requisitos Previos

- **Docker** >= 24.0
- **Docker Compose** >= 2.20
- **Git**
- **RAM mínima:** 8 GB (Elasticsearch requiere ~2 GB)
- **Disco:** 10 GB libres

## Inicio Rápido

```bash
# 1. Clonar el repositorio
git clone https://github.com/tu-usuario/proyecto-final-devops.git
cd proyecto-final-devops

# 2. Configurar variables de entorno
cp .env.example .env
# Editar .env con valores deseados

# 3. Construir y levantar toda la infraestructura
docker compose up -d --build

# 4. Verificar que todos los servicios están corriendo
docker compose ps

# 5. Inicializar Vault con secretos
chmod +x vault/init-vault.sh
./vault/init-vault.sh

# 6. Ver logs de todos los servicios
docker compose logs -f
```

## Servicios y Puertos

| Servicio       | Puerto | URL                          | Credenciales        |
|----------------|--------|------------------------------|---------------------|
| Aplicación     | 80     | http://localhost             | -                   |
| Prometheus     | 9090   | http://localhost:9090        | -                   |
| Grafana        | 3000   | http://localhost:3000        | admin / admin123    |
| Kibana         | 5601   | http://localhost:5601        | -                   |
| Elasticsearch  | 9200   | http://localhost:9200        | -                   |
| Vault          | 8200   | http://localhost:8200        | Token: dev-root-token |

## Observabilidad

### Stack ELK (Logs)

- **Filebeat** recolecta logs de todos los contenedores Docker automáticamente
- Los logs de la aplicación están en formato **JSON estructurado** con campos: timestamp, level, service, hostname, module
- **Elasticsearch** almacena y permite búsquedas sobre los logs
- **Kibana** visualiza los logs. Para configurar:
  1. Ir a http://localhost:5601
  2. Menu → Stack Management → Data Views
  3. Crear data view con patrón `filebeat-*`
  4. Seleccionar `@timestamp` como campo de tiempo

### Prometheus + Grafana (Métricas)

- La aplicación expone métricas en `/metrics` (formato Prometheus)
- **Métricas disponibles:**
  - `app_request_total` — contador de requests por método, endpoint y status
  - `app_request_duration_seconds` — histograma de latencia
  - `app_active_requests` — gauge de requests concurrentes
  - `app_info` — información de versión y hostname
- **Grafana** tiene un dashboard pre-configurado ("Flask App - Observabilidad") con:
  - Requests por segundo
  - Tasa de errores 5xx
  - Latencia p50/p95/p99
  - Estado UP/DOWN de instancias
  - Distribución de requests por endpoint y status

### Alertas

Reglas configuradas en Prometheus (`prometheus/alert_rules.yml`):

| Alerta               | Condición                     | Severidad |
|----------------------|-------------------------------|-----------|
| HighErrorRate        | >5% errores 5xx en 5 min     | critical  |
| HighLatency          | p95 > 1 segundo por 3 min    | warning   |
| InstanceDown         | Instancia caída > 1 min      | critical  |
| HighActiveRequests   | >50 requests concurrentes    | warning   |
| TargetDown           | Cualquier target caído 3 min | critical  |

Verificar alertas: http://localhost:9090/alerts

## Seguridad (DevSecOps)

### Gestión de Secretos (Vault)

- HashiCorp Vault almacena secretos de la aplicación
- Los secretos se inyectan como variables de entorno
- El archivo `.env` **nunca** se commitea al repositorio (está en `.gitignore`)
- El script `vault/init-vault.sh` configura los secretos iniciales

### Escaneo de Vulnerabilidades (Trivy)

El escaneo se ejecuta en 3 niveles:

1. **Imagen Docker** — vulnerabilidades del SO y paquetes
2. **Dependencias** — CVEs en librerías Python
3. **Configuración IaC** — problemas en Dockerfile y docker-compose.yml

```bash
# Ejecutar escaneo manual
chmod +x security/trivy-scan.sh
./security/trivy-scan.sh
```

### Integración en CI/CD

El pipeline de GitHub Actions incluye un **gate de seguridad**: si Trivy encuentra vulnerabilidades **CRITICAL**, el deploy se bloquea automáticamente.

### Hardening Implementado

| Medida                        | Implementación                                 |
|------------------------------|------------------------------------------------|
| Usuario no-root              | `USER appuser` en Dockerfile                   |
| Filesystem read-only         | `read_only: true` en docker-compose            |
| Multi-stage build            | Reduce superficie de ataque en imagen final    |
| No new privileges            | Recomendado en daemon.json                     |
| Headers de seguridad         | X-Content-Type-Options, X-Frame-Options, etc.  |
| server_tokens off            | Nginx no revela versión                        |
| Logs limitados               | max-size 10m, max-file 3                       |
| Red aislada                  | Bridge network dedicada                        |
| Secretos no en código        | .env + Vault                                   |

```bash
# Verificar hardening
chmod +x security/hardening.sh
./security/hardening.sh
```

## Operaciones en Producción

### 1. Gestión de Fallos y Reinicios Automáticos

- **`restart: unless-stopped`** en todos los servicios
- **Health checks** integrados en Docker:
  - App: `curl http://localhost:5000/health` cada 30s
  - Elasticsearch: verifica cluster health cada 30s
- **Dependencias**: Kibana espera a que Elasticsearch esté healthy

**Simular fallo y verificar reinicio:**
```bash
# Matar una instancia
docker kill app-2

# Verificar que se reinicia automáticamente
docker compose ps
# Después de ~30s, app-2 estará running de nuevo
```

### 2. Balanceo de Carga

- **Nginx** distribuye tráfico entre 3 instancias con `least_conn`
- Verificar distribución:
```bash
# Hacer 10 requests y ver qué instancia responde
for i in $(seq 1 10); do
  curl -s http://localhost | python3 -c "import sys,json; print(json.load(sys.stdin)['hostname'])"
done
```

### 3. Gestión de Releases (CI/CD)

El pipeline gestiona el ciclo completo de release:

1. **Build** — Construye imagen Docker con tag semántico
2. **Test** — Ejecuta tests unitarios con pytest
3. **Scan** — Escaneo de seguridad con Trivy (bloquea si hay CRITICAL)
4. **Deploy** — Solo si tests y scan pasan, solo en branch `main` o tags `v*`
5. **Release** — Crea GitHub Release automático en tags

**Crear un release:**
```bash
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0
```

## Pruebas y Verificación

### Generar tráfico de prueba

```bash
# Requests normales
for i in $(seq 1 50); do curl -s http://localhost > /dev/null; done

# Crear items
curl -X POST http://localhost/api/items \
  -H "Content-Type: application/json" \
  -d '{"name": "Test Item", "category": "prueba"}'

# Simular errores (para activar alertas)
for i in $(seq 1 20); do curl -s http://localhost/api/simulate/error > /dev/null; done

# Simular latencia alta
curl http://localhost/api/simulate/slow
```

### Verificar observabilidad

1. **Prometheus**: http://localhost:9090/targets — todos los targets deben estar UP
2. **Grafana**: http://localhost:3000 — dashboard "Flask App - Observabilidad"
3. **Kibana**: http://localhost:5601 — buscar logs en Discover
4. **Alertas**: http://localhost:9090/alerts — verificar reglas activas

### Verificar seguridad

```bash
# Ejecutar escaneo Trivy
./security/trivy-scan.sh

# Verificar hardening
./security/hardening.sh

# Verificar que Vault tiene secretos
curl -H "X-Vault-Token: dev-root-token" http://localhost:8200/v1/secret/data/flask-app
```

### Detener todo

```bash
docker compose down            # Detener servicios
docker compose down -v         # Detener y eliminar volúmenes
```

## Estructura del Repositorio

```
├── .github/workflows/
│   └── ci-cd.yml              # Pipeline CI/CD (GitHub Actions)
├── app/
│   ├── Dockerfile             # Imagen Docker (multi-stage, hardened)
│   ├── app.py                 # Aplicación Flask
│   ├── requirements.txt       # Dependencias Python
│   └── tests/
│       └── test_app.py        # Tests unitarios
├── nginx/
│   └── nginx.conf             # Balanceador de carga
├── prometheus/
│   ├── prometheus.yml         # Configuración de scraping
│   └── alert_rules.yml        # Reglas de alertamiento
├── grafana/provisioning/
│   ├── dashboards/
│   │   ├── dashboard.yml      # Provisioning de dashboards
│   │   └── app-dashboard.json # Dashboard pre-configurado
│   └── datasources/
│       └── datasource.yml     # Prometheus + Elasticsearch
├── elk/filebeat/
│   └── filebeat.yml           # Recolección de logs Docker
├── vault/
│   └── init-vault.sh          # Inicialización de secretos
├── security/
│   ├── trivy-scan.sh          # Escaneo de vulnerabilidades
│   └── hardening.sh           # Verificación de hardening
├── docs/
│   ├── arquitectura.md        # Documentación de arquitectura
│   ├── observabilidad.md      # Documentación de monitoreo
│   ├── seguridad.md           # Documentación de seguridad
│   └── operaciones.md         # Documentación de operaciones
├── docker-compose.yml         # Infraestructura completa
├── .env.example               # Variables de entorno (ejemplo)
├── .gitignore                 # Archivos excluidos
└── README.md                  # Esta guía
```
