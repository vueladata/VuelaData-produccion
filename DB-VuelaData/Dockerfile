FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

ENV DB_HOST=postgres \
    DB_PORT=5432 \
    DB_NAME=vueladata_db \
    DB_USER=postgres \
    DB_PASSWORD=postgres

CMD ["python", "seed.py", "--volumen", "small", "--tasa-defectos", "0.1"]
