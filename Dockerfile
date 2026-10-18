FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    VUELADATA_DATA_DIR=/app/data

WORKDIR /app

COPY pyproject.toml README.md ./
COPY src ./src
RUN pip install --no-cache-dir .

COPY database ./database
COPY data/reference ./data/reference

RUN useradd --create-home --uid 10001 appuser \
    && mkdir -p /app/data/generated \
    && chown -R appuser:appuser /app

USER appuser
EXPOSE 8000

CMD ["uvicorn", "vueladata.api.main:app", "--host", "0.0.0.0", "--port", "8000"]
