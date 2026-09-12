from contextlib import contextmanager
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool
from .config import settings

_pool: ConnectionPool | None = None

def get_pool() -> ConnectionPool:
    global _pool
    if _pool is None:
        if not settings.database_url:
            raise RuntimeError("DATABASE_URL is not configured.")
        _pool = ConnectionPool(
            conninfo=settings.database_url,
            min_size=1,
            max_size=10,
            kwargs={"row_factory": dict_row},
            open=True,
        )
    return _pool

@contextmanager
def get_connection():
    with get_pool().connection() as conn:
        yield conn

def close_pool() -> None:
    global _pool
    if _pool is not None:
        _pool.close()
        _pool = None
