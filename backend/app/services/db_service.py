from uuid import UUID
from datetime import date, datetime
from decimal import Decimal
from psycopg import sql
from app.core.database import get_connection

def _json_value(value):
    if isinstance(value, (UUID, date, datetime, Decimal)):
        return str(value)
    if isinstance(value, dict):
        return {k: _json_value(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_json_value(v) for v in value]
    return value

def list_rows(schema: str, table: str, limit: int, offset: int):
    query = sql.SQL("SELECT * FROM {}.{} LIMIT %s OFFSET %s").format(
        sql.Identifier(schema), sql.Identifier(table)
    )
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(query, (limit, offset))
            return [_json_value(dict(row)) for row in cur.fetchall()]

def get_row(schema: str, table: str, pk: str, value):
    query = sql.SQL("SELECT * FROM {}.{} WHERE {} = %s").format(
        sql.Identifier(schema), sql.Identifier(table), sql.Identifier(pk)
    )
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(query, (value,))
            row = cur.fetchone()
            return _json_value(dict(row)) if row else None

def count_rows(schema: str, table: str):
    query = sql.SQL("SELECT count(*) AS count FROM {}.{}").format(
        sql.Identifier(schema), sql.Identifier(table)
    )
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(query)
            return int(cur.fetchone()["count"])

def health_check():
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT current_database() AS database")
            return dict(cur.fetchone())
