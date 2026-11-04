from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Read from environment variables (case-insensitive)."""

    # Full SQLAlchemy URL - used for local dev / tests. If set, DB_* is ignored.
    database_url: str | None = None

    db_host: str = "localhost"
    db_port: int = 5432
    db_name: str = "orders"
    db_user: str = "orders"
    db_password: str | None = None
    # Path to a file containing the password (Key Vault CSI driver mount).
    # Read on every new connection, so rotated secrets are picked up without a restart.
    db_password_file: str | None = None
    db_sslmode: str = "require"

    log_level: str = "INFO"
