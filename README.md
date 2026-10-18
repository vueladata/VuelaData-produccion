# VuelaData

VuelaData is an integrated airline operations and data platform. The repository is organized as one Python application with domain modules for the REST API, fleet itinerary generation, database seeding, and OOOI event simulation.

## Architecture

- **FastAPI** exposes the operational API and its OpenAPI documentation.
- **PostgreSQL** stores operational data. The schema is initialized when the database volume is first created.
- **Fleet itinerary generator (F6)** creates route, fleet, and weekly itinerary CSV files automatically at startup. Files are written to `data/generated/` on the host.
- **RabbitMQ** transports OOOI events between the F4 producer and consumer.
- **Database seed** loads reproducible sample data after PostgreSQL becomes healthy.
- **Docker Compose** coordinates startup and waits for prerequisite services and one-shot jobs.

## Start the full environment

Docker Desktop must be running. From the repository root, run:

```powershell
docker compose up --build
```

No separate script or per-module startup command is required. On startup, Compose builds the application image, starts PostgreSQL and RabbitMQ, generates the F6 CSV files, seeds PostgreSQL, starts the API, publishes OOOI events, and runs the consumer that acknowledges them.

> The first run downloads base images and Python dependencies, so it can take several minutes.

## Local endpoints

| Component | Address |
| --- | --- |
| API health | http://localhost:8000/health |
| Database health | http://localhost:8000/health/db |
| OpenAPI / Swagger | http://localhost:8000/docs |
| RabbitMQ management | http://localhost:15672 |
| PostgreSQL | `localhost:5434` |

Default local development credentials are provided by Compose for convenience. Change them for any shared or deployed environment, and never commit a real `.env` file.

## Generated CSV files

After the `fleet_generate` job completes, these files should exist in `data/generated/`:

- `synthetic_routes.csv`
- `synthetic_fleet.csv`
- `synthetic_weekly_itinerary.csv`

The generator validates the weekly schedule before writing the files. If validation fails, the job exits with an error and the startup chain does not silently continue as if generation succeeded.

## Useful commands

```powershell
# See running and completed services
docker compose ps -a

# Inspect service logs
docker compose logs -f api db_seed fleet_generate oooi_producer oooi_consumer

# Stop services (keeps database data)
docker compose down

# Reset the local database volume and reinitialize from scratch
# WARNING: this deletes the local PostgreSQL volume
docker compose down -v
```

## Repository structure

```text
vueladata/
├── src/vueladata/
│   ├── api/                 # FastAPI routers, models, schemas and CRUD
│   ├── fleet/itinerary/     # F6 CSV generator
│   ├── operations/oooi/     # F4 OOOI event producer and generator
│   └── data/                # PostgreSQL seed process
├── data/reference/          # Canonical airport and airline source files
├── data/generated/          # Generated CSV output (not committed)
├── database/schema.sql      # PostgreSQL schema
├── tests/                   # Automated tests
├── docs/                    # Project documentation in Markdown
├── Dockerfile               # Shared application image
├── compose.yaml             # Integrated local environment
└── pyproject.toml           # Python package and dependencies
```

## Notes

- PostgreSQL and RabbitMQ use their official images; they do not need custom Dockerfiles.
- Python jobs share the same application image and package. Their Compose commands determine whether they run the API or a one-shot task.
- The F6 CSVs are generated automatically. The existing database seed independently populates the relational operational model; mapping F6 output columns into relational tables is a separate data-integration step and is not implied by CSV generation alone.
