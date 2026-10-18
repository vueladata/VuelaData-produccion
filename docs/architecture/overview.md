# Architecture overview

VuelaData is maintained as one repository and one Python package. The runtime is composed of one application image plus PostgreSQL and RabbitMQ infrastructure containers.

## Startup flow

1. PostgreSQL initializes its schema and passes its health check.
2. RabbitMQ starts and passes its health check.
3. The F6 one-shot job generates and validates the route, fleet, and itinerary CSVs.
4. The database seed inserts sample operational data.
5. FastAPI starts after PostgreSQL and the seed job are ready.
6. The OOOI producer publishes simulated events to the durable RabbitMQ queue.
7. The OOOI consumer receives, validates as JSON, logs, and acknowledges each event.

The F6 CSV generator and database seed are separate jobs. CSV generation does not automatically import those CSVs into PostgreSQL; that mapping should be implemented explicitly if the database must use the generated schedule as its source of truth.
