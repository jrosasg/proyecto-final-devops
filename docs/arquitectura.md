# Documentación de Arquitectura

## Visión General

La plataforma está diseñada como una infraestructura local completa que integra desarrollo, seguridad y operaciones bajo los principios de DevOps y DevSecOps. Todos los componentes se ejecutan en contenedores Docker orquestados con Docker Compose.

## Componentes

### Aplicación (Flask + Gunicorn)

La aplicación es una API REST construida con Flask que incluye instrumentación nativa para observabilidad:

- **Logs estructurados**: formato JSON con campos estandarizados (timestamp, level, service, hostname) que facilitan la ingesta y búsqueda en Elasticsearch.
- **Métricas Prometheus**: contadores, histogramas y gauges expuestos en `/metrics` para monitoreo en tiempo real.
- **Health checks**: endpoints `/health` y `/ready` para verificación de estado por parte de Docker y el balanceador.

Se ejecuta con Gunicorn (2 workers) en 3 instancias independientes para demostrar escalabilidad horizontal.

### Balanceador de Carga (Nginx)

Nginx actúa como reverse proxy y distribuidor de carga con algoritmo `least_conn` (envía al servidor con menos conexiones activas). Es el único punto de entrada a la aplicación, exponiendo el puerto 80.

Incluye headers de seguridad (X-Content-Type-Options, X-Frame-Options, X-XSS-Protection) y logs en formato JSON para su recolección por Filebeat.

### Stack de Observabilidad

Dos pipelines complementarios:

1. **Logs**: Filebeat → Elasticsearch → Kibana. Filebeat auto-descubre contenedores Docker, parsea los logs JSON de la aplicación y los envía a Elasticsearch.
2. **Métricas**: App `/metrics` → Prometheus (scraping cada 15s) → Grafana (dashboards pre-configurados).

### Seguridad

HashiCorp Vault centraliza la gestión de secretos. En desarrollo se usa modo `dev` con token conocido; en producción se usaría modo sellado con unseal keys.

Trivy escanea en 3 niveles: imagen Docker, dependencias Python y configuración IaC.

### Red

Todos los servicios comparten una red bridge (`app-net`). Solo Nginx expone puertos al host. Los servicios internos se comunican por nombre de contenedor (DNS interno de Docker).

## Decisiones de Diseño

| Decisión | Justificación |
|----------|---------------|
| Flask sobre Django | Más liviano, suficiente para demostrar observabilidad |
| Filebeat sobre Logstash | Menor consumo de recursos para recolección de logs |
| 3 instancias de app | Mínimo para demostrar load balancing efectivo |
| Prometheus pull-model | Estándar de la industria, no requiere agente en la app |
| Multi-stage Docker build | Reduce tamaño de imagen y superficie de ataque |
| Gunicorn como WSGI | Production-ready, manejo eficiente de concurrencia |
