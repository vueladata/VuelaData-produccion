# Development and validation

## Automated tests

Install the project and development dependencies, then run:

```bash
uv sync --all-groups
uv run pytest
```

The API CRUD tests require a reachable PostgreSQL database with the VuelaData schema and seed data. For a complete integration check, start the stack with Docker Compose and verify `/health`, `/health/db`, the OpenAPI document, generated CSVs, and the RabbitMQ queue.

## Integration acceptance checklist

- [ ] `docker compose up --build` starts the integrated environment without manually running scripts.
- [ ] `data/generated/synthetic_routes.csv` exists.
- [ ] `data/generated/synthetic_fleet.csv` exists.
- [ ] `data/generated/synthetic_weekly_itinerary.csv` exists.
- [ ] `/health` returns HTTP 200.
- [ ] `/health/db` returns HTTP 200 after seed completion.
- [ ] `/docs` and `/openapi.json` return HTTP 200.
- [ ] The OOOI producer publishes events and the integrated consumer receives and acknowledges them; verify both service logs.
- [ ] `db_seed`, `fleet_generate`, and `oooi_producer` finish with exit code 0.
