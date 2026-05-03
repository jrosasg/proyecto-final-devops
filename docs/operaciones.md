# Documentación de Operaciones en Producción

## Capacidades Implementadas

Se implementan las 3 opciones del enunciado:

1. Gestión de fallos y reinicios automáticos
2. Balanceador de carga con múltiples instancias
3. Gestión de releases mediante CI/CD

## 1. Gestión de Fallos y Reinicios Automáticos

### Política de Reinicio

Todos los servicios tienen la política `restart: unless-stopped`, lo que significa que Docker reiniciará automáticamente cualquier contenedor que se detenga inesperadamente, excepto si fue detenido manualmente por el operador.

### Health Checks

La aplicación Flask expone dos endpoints de verificación:

**`/health`** — Verifica que el proceso de la aplicación está corriendo y puede responder requests. Retorna el uptime del servicio. Docker lo consulta cada 30 segundos con un timeout de 5 segundos. Tras 3 fallos consecutivos el contenedor se marca como unhealthy.

**`/ready`** — Verifica que la aplicación está lista para recibir tráfico. En un entorno con base de datos, este endpoint verificaría la conexión a la BD, cache, etc.

**Elasticsearch** tiene su propio health check que verifica el estado del cluster. Kibana depende de que Elasticsearch esté healthy antes de iniciar (`condition: service_healthy`).

### Pruebas de Fallos

```bash
# Verificar estado actual
docker compose ps

# Simular crash de una instancia
docker kill app-2

# Observar reinicio automático (esperar ~30 segundos)
watch docker compose ps

# Simular fallo de Elasticsearch
docker stop elasticsearch
# Filebeat dejará de enviar logs pero los almacenará en buffer
# Kibana mostrará error de conexión
docker start elasticsearch
# Los logs almacenados en buffer se enviarán automáticamente

# Simular fallo completo de todas las instancias
docker kill app-1 app-2 app-3
# Las 3 se reiniciarán automáticamente
# Nginx devolverá 502 temporalmente hasta que las instancias estén ready
```

## 2. Balanceador de Carga

### Configuración

Nginx actúa como balanceador de carga frente a 3 instancias de la aplicación Flask. Utiliza el algoritmo `least_conn` que envía cada nueva conexión al servidor con menos conexiones activas en ese momento.

```
Nginx (puerto 80) → app-1:5000, app-2:5000, app-3:5000
```

### Verificación de Distribución

```bash
# Hacer 20 requests y ver la distribución
for i in $(seq 1 20); do
  curl -s http://localhost | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f\"Request {$i}: {data['hostname']}\")"
done

# Resultado esperado: distribución balanceada entre app-1, app-2, app-3
```

### Prueba de Escalabilidad

```bash
# Reducir a 1 instancia
docker stop app-2 app-3
# La aplicación sigue funcionando con app-1

# Restaurar las 3 instancias
docker start app-2 app-3

# Simular carga con requests concurrentes
for i in $(seq 1 100); do
  curl -s http://localhost > /dev/null &
done
wait
echo "100 requests completados"
```

### Prueba con una Instancia Caída

```bash
# Detener app-3 permanentemente
docker stop app-3

# Nginx detecta que app-3 no responde y distribuye entre app-1 y app-2
for i in $(seq 1 10); do
  curl -s http://localhost | python3 -c "import sys,json; print(json.load(sys.stdin)['hostname'])"
done
# Solo debería mostrar app-1 y app-2

docker start app-3
```

## 3. Gestión de Releases (CI/CD)

### Flujo del Pipeline

El pipeline de GitHub Actions gestiona el ciclo completo de un release:

```
Push/PR → Build → Test → Security Scan → Deploy → Release
```

**Build:** Construye la imagen Docker con tags semánticos (versión del tag git, SHA del commit, latest para main).

**Test:** Ejecuta la suite completa de tests unitarios con pytest. Si algún test falla, el pipeline se detiene.

**Security Scan:** Trivy escanea la imagen, dependencias y configuración. Si detecta vulnerabilidades CRITICAL, el deploy se bloquea.

**Deploy:** Solo se ejecuta en branch `main` o en tags `v*`. En un entorno con self-hosted runner, ejecutaría `docker compose up -d` en el servidor de producción.

**Release:** En tags `v*`, crea automáticamente un GitHub Release con notas de release generadas y los reportes de seguridad como adjuntos.

### Crear un Release

```bash
# Asegurarse de estar en main con todo comiteado
git checkout main
git pull

# Crear tag de versión
git tag -a v1.0.0 -m "Release v1.0.0: Plataforma inicial"
git push origin v1.0.0

# El pipeline:
# 1. Construye la imagen con tag v1.0.0
# 2. Ejecuta tests
# 3. Escanea seguridad
# 4. Despliega (si todo pasa)
# 5. Crea GitHub Release automáticamente
```

### Estrategia de Versionado

Se utiliza Semantic Versioning (SemVer):
- `MAJOR.MINOR.PATCH` (ejemplo: v1.2.3)
- MAJOR: cambios incompatibles
- MINOR: funcionalidad nueva compatible
- PATCH: correcciones de bugs

La versión se inyecta como variable de entorno `APP_VERSION` y se expone en el endpoint raíz (`/`) y en la métrica `app_info` de Prometheus.
