# VuelaData Workspace

Este repositorio reúne la infraestructura base de VuelaData para levantar de una sola vez los servicios principales del proyecto en Docker.

## Arquitectura del workspace

El proyecto está dividido en varios módulos funcionales dentro del mismo workspace:

- API-VuelaData: backend FastAPI con PostgreSQL y endpoints operativos.
- DB-VuelaData: generador de datos sintéticos y sembrado inicial de la base de datos.
- Stream-VuelaData: simulador de eventos OOOI con RabbitMQ.
- F6-csv-VuelaData: generación de CSVs de rutas, flota e itinerarios.
- DB-VuelaData/schema_postgresql.sql: esquema relacional principal de la base de datos.

## Qué se levanta con Docker Compose

Desde la raíz del workspace, el comando:

```bash
docker compose up
```

levanta estos servicios:

- PostgreSQL: base de datos principal
- API FastAPI: backend operativo de VuelaData
- RabbitMQ: broker para eventos del módulo Stream F4
- DB-VuelaData seed: carga inicial de datos sintéticos en PostgreSQL

## Servicios y puertos

| Servicio | URL / Puerto | Descripción |
| --- | --- | --- |
| API FastAPI | http://localhost:8000 | Backend principal |
| Swagger | http://localhost:8000/docs | Documentación OpenAPI |
| PostgreSQL | localhost:5434 | Base de datos relacional |
| RabbitMQ | localhost:5672 | Broker AMQP |
| RabbitMQ UI | http://localhost:15672 | Administración RabbitMQ |

## Variables de entorno

La raíz del workspace incluye el archivo `.env` con la configuración base. Los valores más importantes son:

```env
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_DB=vueladata_db
POSTGRES_PORT=5434
API_PORT=8000
RABBITMQ_PORT=5672
RABBITMQ_MGMT_PORT=15672
RABBITMQ_DEFAULT_USER=admin
RABBITMQ_DEFAULT_PASS=admin123
```

## Cómo levantar todo el proyecto

Desde la carpeta raíz:

```bash
docker compose up -d --build
```

Esto construye las imágenes necesarias y levanta la pila completa.

Si quieres reiniciar desde cero:

```bash
docker compose down

docker compose up -d --build
```

## Verificación rápida

Después de levantar la pila, puedes comprobar:

```bash
curl http://localhost:8000/health
curl http://localhost:8000/health/db
```

Debe devolver respuestas con estado `200 OK`.

También puedes revisar los contenedores activos:

```bash
docker compose ps
```

## Nota importante sobre la base de datos

La base de datos del proyecto usa el esquema definido en:

- [DB-VuelaData/schema_postgresql.sql](DB-VuelaData/schema_postgresql.sql)

Al iniciar el compose, se inicializa automáticamente con ese esquema y el seed de datos sintéticos del módulo DB-VuelaData.

## Recomendación de uso

- Para trabajar con la API y la base de datos: usa el arranque raíz con Docker Compose.
- Para generar CSVs del módulo F6: entra a la carpeta correspondiente y ejecuta el script del generador manualmente si lo necesitas.
- Para el flujo de eventos F4: RabbitMQ queda levantado y listo para usar desde el módulo Stream-VuelaData.

## Estructura relevante del workspace

```text
vueladata-workspace/
├── docker-compose.yml
├── .env
├── README.md
├── API-VuelaData/
├── DB-VuelaData/
├── F6-csv-VuelaData/
├── Stream-VuelaData/
└── ...
```
