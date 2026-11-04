from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    app_title: str = "Orders Platform"
    environment: str = "local"
    # Browser calls the API on the same host through Kong (/api/*) - no CORS needed.
    api_base_path: str = "/api"
    log_level: str = "INFO"
