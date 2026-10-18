"""Consume and acknowledge OOOI events from the durable RabbitMQ queue."""

import json
import os
import time

import pika

RABBITMQ_HOST = os.getenv("RABBITMQ_HOST", "rabbitmq")
RABBITMQ_USER = os.getenv("RABBITMQ_USER", "admin")
RABBITMQ_PASS = os.getenv("RABBITMQ_PASS", "dev_rabbitmq_password")
QUEUE_NAME = os.getenv("QUEUE_NAME", "eventos_oooi_queue")
MAX_ATTEMPTS = int(os.getenv("RABBITMQ_MAX_ATTEMPTS", "30"))


def connect_to_rabbitmq():
    """Connect with retries so startup order does not cause a permanent failure."""
    credentials = pika.PlainCredentials(RABBITMQ_USER, RABBITMQ_PASS)
    parameters = pika.ConnectionParameters(
        host=RABBITMQ_HOST,
        credentials=credentials,
        heartbeat=60,
        blocked_connection_timeout=30,
    )

    for attempt in range(1, MAX_ATTEMPTS + 1):
        try:
            connection = pika.BlockingConnection(parameters)
            channel = connection.channel()
            channel.queue_declare(queue=QUEUE_NAME, durable=True)
            channel.basic_qos(prefetch_count=20)
            return connection, channel
        except Exception as exc:
            if attempt == MAX_ATTEMPTS:
                raise RuntimeError("Could not connect to RabbitMQ after retries") from exc
            wait_seconds = min(attempt, 5)
            print(
                f"RabbitMQ is not ready. Retry {attempt}/{MAX_ATTEMPTS} "
                f"in {wait_seconds}s: {exc}",
                flush=True,
            )
            time.sleep(wait_seconds)

    raise RuntimeError("RabbitMQ connection attempts exhausted")


def on_message(channel, method, properties, body):
    """Validate the JSON message and acknowledge only successfully decoded events."""
    try:
        event = json.loads(body)
        print(
            "OOOI event received: "
            f"flight={event.get('numero_vuelo')} "
            f"event={event.get('codigo_evento')} "
            f"timestamp={event.get('fecha_hora_evento_utc')}",
            flush=True,
        )
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        print(f"Invalid OOOI message rejected: {exc}", flush=True)
        channel.basic_nack(delivery_tag=method.delivery_tag, requeue=False)
        return

    channel.basic_ack(delivery_tag=method.delivery_tag)


def main():
    connection, channel = connect_to_rabbitmq()
    channel.basic_consume(queue=QUEUE_NAME, on_message_callback=on_message)
    print(f"OOOI consumer listening on queue '{QUEUE_NAME}'.", flush=True)
    try:
        channel.start_consuming()
    finally:
        if connection.is_open:
            connection.close()


if __name__ == "__main__":
    main()
