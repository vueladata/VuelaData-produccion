from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    # Compose sobrescribe este valor; el default permite importar modelos y ejecutar pruebas locales.
    database_url: str = "postgresql+psycopg://vueladata:dev_postgres_password@localhost:5434/vueladata"

    model_config = {"env_file": ".env",
                    "extra": "ignore"}   # y también del archivo .env

settings = Settings()