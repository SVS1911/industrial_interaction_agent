import os
from dataclasses import dataclass

from dotenv import load_dotenv

load_dotenv()


def get_cors_origins() -> tuple[str, ...]:
    value = os.getenv(
        "CORS_ORIGINS",
        "http://localhost:5173,http://127.0.0.1:5173",
    )

    return tuple(
        origin.strip()
        for origin in value.split(",")
        if origin.strip()
    )


@dataclass(frozen=True)
class Settings:
    app_name: str = os.getenv(
        "APP_NAME",
        "Industry Interaction Agent Backend",
    )

    app_env: str = os.getenv(
        "APP_ENV",
        "development",
    )

    app_host: str = os.getenv(
        "APP_HOST",
        "127.0.0.1",
    )

    app_port: int = int(
        os.getenv("APP_PORT", "8000")
    )

    database_url: str = os.getenv(
        "DATABASE_URL",
        "",
    )

    psql_path: str = os.getenv(
        "PSQL_PATH",
        "psql",
    )

    gemini_api_key: str = os.getenv(
        "GEMINI_API_KEY",
        "",
    )

    gemini_model: str = os.getenv(
        "GEMINI_MODEL",
        "gemini-3.8-flash",
    )

    cors_origins: tuple[str, ...] = get_cors_origins()


settings = Settings()