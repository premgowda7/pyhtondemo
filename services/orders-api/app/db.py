from sqlalchemy import URL, create_engine, event
from sqlalchemy.engine import Engine
from sqlalchemy.orm import DeclarativeBase
from sqlalchemy.pool import StaticPool

from .config import Settings


class Base(DeclarativeBase):
    pass


def read_password(settings: Settings) -> str:
    if settings.db_password_file:
        with open(settings.db_password_file, encoding="utf-8") as f:
            return f.read().strip()
    return settings.db_password or ""


def build_engine(settings: Settings) -> Engine:
    if settings.database_url:
        kwargs = {}
        if settings.database_url.startswith("sqlite"):
            kwargs = {"connect_args": {"check_same_thread": False}, "poolclass": StaticPool}
        return create_engine(settings.database_url, **kwargs)

    url = URL.create(
        "postgresql+psycopg",
        username=settings.db_user,
        host=settings.db_host,
        port=settings.db_port,
        database=settings.db_name,
    )
    engine = create_engine(
        url,
        pool_pre_ping=True,  # drop dead connections (PE / failover blips)
        pool_size=5,
        max_overflow=5,
        pool_recycle=1800,
        connect_args={"sslmode": settings.db_sslmode, "connect_timeout": 5},
    )

    @event.listens_for(engine, "do_connect")
    def _inject_password(dialect, conn_rec, cargs, cparams):  # noqa: ARG001
        cparams["password"] = read_password(settings)

    return engine
