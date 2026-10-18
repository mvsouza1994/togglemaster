"""Fixtures dos testes: o app conecta no Postgres no import, entao o pool e mockado antes."""
import os
from unittest import mock

import pytest

os.environ.setdefault("DATABASE_URL", "postgresql://teste:teste@localhost:5432/teste")
os.environ.setdefault("AUTH_SERVICE_URL", "http://auth.teste")

# troca o pool real por um mock antes de importar o app
_pool_patch = mock.patch("psycopg2.pool.SimpleConnectionPool")
_pool_class = _pool_patch.start()

import app as app_module  # noqa: E402


@pytest.fixture
def cursor():
    """Cursor falso devolvido pelo pool mockado."""
    cur = mock.MagicMock()
    conn = mock.MagicMock()
    conn.cursor.return_value = cur
    app_module.pool = mock.MagicMock()
    app_module.pool.getconn.return_value = conn
    cur.conn = conn
    return cur


@pytest.fixture
def client():
    app_module.app.config["TESTING"] = True
    with app_module.app.test_client() as c:
        yield c


@pytest.fixture
def auth_ok():
    """Simula o auth-service aceitando a chave."""
    with mock.patch.object(app_module.requests, "get") as get:
        get.return_value.status_code = 200
        yield get


AUTH = {"Authorization": "Bearer tm_key_teste"}
