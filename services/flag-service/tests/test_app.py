"""Testes unitarios do flag-service (sem banco e sem auth-service reais)."""
from unittest import mock

import psycopg2
import requests

import app as app_module
from conftest import AUTH


def test_health(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.get_json() == {"status": "ok"}


def test_sem_authorization_retorna_401(client):
    assert client.get("/flags").status_code == 401


def test_chave_invalida_retorna_401(client):
    with mock.patch.object(app_module.requests, "get") as get:
        get.return_value.status_code = 401
        assert client.get("/flags", headers=AUTH).status_code == 401


def test_auth_service_fora_do_ar_retorna_503(client):
    with mock.patch.object(app_module.requests, "get", side_effect=requests.exceptions.ConnectionError()):
        assert client.get("/flags", headers=AUTH).status_code == 503


def test_auth_service_timeout_retorna_504(client):
    with mock.patch.object(app_module.requests, "get", side_effect=requests.exceptions.Timeout()):
        assert client.get("/flags", headers=AUTH).status_code == 504


def test_criar_flag_sem_nome_retorna_400(client, auth_ok):
    assert client.post("/flags", json={"description": "x"}, headers=AUTH).status_code == 400


def test_criar_flag(client, auth_ok, cursor):
    cursor.fetchone.return_value = {"id": 1, "name": "nova", "is_enabled": True}
    resp = client.post("/flags", json={"name": "nova", "is_enabled": True}, headers=AUTH)
    assert resp.status_code == 201
    assert resp.get_json()["name"] == "nova"
    cursor.conn.commit.assert_called_once()


def test_criar_flag_duplicada_retorna_409(client, auth_ok, cursor):
    cursor.execute.side_effect = psycopg2.IntegrityError()
    resp = client.post("/flags", json={"name": "dup"}, headers=AUTH)
    assert resp.status_code == 409
    cursor.conn.rollback.assert_called_once()


def test_buscar_flag_inexistente_retorna_404(client, auth_ok, cursor):
    cursor.fetchone.return_value = None
    assert client.get("/flags/nao-existe", headers=AUTH).status_code == 404


def test_listar_flags(client, auth_ok, cursor):
    cursor.fetchall.return_value = [{"name": "a"}, {"name": "b"}]
    resp = client.get("/flags", headers=AUTH)
    assert resp.status_code == 200
    assert len(resp.get_json()) == 2


def test_atualizar_sem_campos_retorna_400(client, auth_ok):
    assert client.put("/flags/a", json={"outro": 1}, headers=AUTH).status_code == 400


def test_atualizar_flag_usa_query_parametrizada(client, auth_ok, cursor):
    cursor.rowcount = 1
    cursor.fetchone.return_value = {"name": "a", "is_enabled": False}
    resp = client.put("/flags/a", json={"is_enabled": False}, headers=AUTH)
    assert resp.status_code == 200
    query, params = cursor.execute.call_args[0]
    assert "is_enabled = %s" in query
    assert params == (False, "a")


def test_deletar_flag_inexistente_retorna_404(client, auth_ok, cursor):
    cursor.rowcount = 0
    assert client.delete("/flags/x", headers=AUTH).status_code == 404


def test_deletar_flag(client, auth_ok, cursor):
    cursor.rowcount = 1
    assert client.delete("/flags/x", headers=AUTH).status_code == 204
