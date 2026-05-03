# Documentación de Observabilidad

## Pilares Implementados

### 1. Logs (ELK Stack)

**Pipeline:** Aplicación → Docker JSON logs → Filebeat → Elasticsearch → Kibana

La aplicación genera logs en formato JSON estructurado con los siguientes campos:

```json
{
  "timestamp": "2024-01-15T10:30:00.000Z",
  "level": "INFO",
  "logger": "app",
  "message": "request",
  "module": "app",
  "function": "after_request",
  "service": "flask-app",
  "hostname": "app-1"
}
```

**Filebeat** está configurado con autodiscovery de Docker, lo que significa que detecta automáticamente nuevos contenedores y comienza a recolectar sus logs. Usa labels de Docker (`app.role`) para aplicar configuraciones específicas por tipo de servicio.

**Configuración de Kibana:**

1. Acceder a http://localhost:5601
2. Ir a Stack Management → Data Views
3. Crear un nuevo data view con patrón `filebeat-*`
4. Seleccionar `@timestamp` como time field
5. Ir a Discover para buscar y filtrar logs

Filtros útiles en Kibana:
- `service: "flask-app"` — solo logs de la aplicación
- `app.level: "ERROR"` — solo errores
- `app.status: 500` — solo errores 500
- `docker.container.name: "app-1"` — logs de una instancia específica

### 2. Métricas (Prometheus + Grafana)

**Pipeline:** Aplicación `/metrics` ← Prometheus (pull cada 15s) → Grafana

**Métricas expuestas por la aplicación:**

| Métrica | Tipo | Descripción |
|---------|------|-------------|
| `app_request_total` | Counter | Total de requests (labels: method, endpoint, status) |
| `app_request_duration_seconds` | Histogram | Latencia con buckets predefinidos |
| `app_active_requests` | Gauge | Requests concurrentes en este momento |
| `app_info` | Gauge | Metadata de la app (version, hostname) |

**Dashboard de Grafana** (pre-configurado, se carga automáticamente):

- Requests por segundo (RPS total)
- Tasa de errores 5xx como porcentaje
- Latencia en percentiles p50, p95, p99
- Requests activos por instancia
- Estado UP/DOWN de cada instancia (semáforo)
- Distribución de requests por endpoint (pie chart)
- Requests por código de status (stacked)

### 3. Alertas

Las reglas de alertamiento están definidas en `prometheus/alert_rules.yml` y se evalúan cada 15 segundos.

**HighErrorRate** — Se dispara cuando más del 5% de los requests generan errores 5xx durante 5 minutos sostenidos. Severidad crítica.

**HighLatency** — Se dispara cuando el percentil 95 de latencia supera 1 segundo durante 3 minutos. Severidad warning.

**InstanceDown** — Se dispara cuando una instancia de la aplicación deja de responder al scraping de Prometheus por más de 1 minuto. Severidad crítica.

**HighActiveRequests** — Se dispara cuando hay más de 50 requests concurrentes en una instancia por más de 2 minutos. Severidad warning.

**TargetDown** — Se dispara cuando cualquier target de Prometheus (incluyendo infraestructura) deja de responder por 3 minutos. Severidad crítica.

Verificar estado de alertas: http://localhost:9090/alerts

## Pruebas de Observabilidad

```bash
# Generar tráfico normal
for i in $(seq 1 100); do curl -s http://localhost > /dev/null; done

# Generar errores (debería activar HighErrorRate)
for i in $(seq 1 50); do curl -s http://localhost/api/simulate/error > /dev/null; done

# Generar latencia alta (debería activar HighLatency)
for i in $(seq 1 5); do curl -s http://localhost/api/simulate/slow > /dev/null & done

# Simular instancia caída (debería activar InstanceDown)
docker stop app-2
# Esperar 1-2 minutos y verificar en Prometheus/Grafana
docker start app-2
```
