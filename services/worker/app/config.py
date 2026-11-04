from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    database_url: str | None = None
    db_host: str = "localhost"
    db_port: int = 5432
    db_name: str = "orders"
    db_user: str = "orders"
    db_password: str | None = None
    db_password_file: str | None = None
    db_sslmode: str = "require"

    poll_interval_seconds: float = 2.0
    batch_size: int = 10
    # Liveness fails if the processing loop has not completed an iteration for this long.
    stall_threshold_seconds: float = 60.0
    log_level: str = "INFO"
