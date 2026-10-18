"""Testes unitarios do targeting-service (sem banco e sem auth-service reais)."""
from unittest import mock

import psycopg2
import requests
from psycopg2.extras import Json

import app as app_module
from conftest import AUTH

REGRA = {"type": "PERCENTAGE", "value": 50}


def test_health(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.get_json() == {"status": "ok"}


def test_sem_authorization_retorna_401(client):
    assert client.get("/rules/a").status_code == 401


def test_auth_service_fora_do_ar_retorna_503(client):
    with mock.patch.object(app_module.requests, "get", side_effect=requests.exceptions.ConnectionError()):
        assert client.get("/rules/a", headers=AUTH).status_code == 503


def test_criar_regra_sem_campos_retorna_400(client, auth_ok):
    assert client.post("/rules", json={"flag_name": "a"}, headers=AUTH).status_code == 400


def test_criar_regra_serializa_json(client, auth_ok, cursor):
    cursor.fetchone.return_value = {"id": 1, "flag_name": "a", "rules": REGRA}
    resp = client.post("/rules", json={"flag_name": "a", "rules": REGRA}, headers=AUTH)
    assert resp.status_code == 201
    params = cursor.execute.call_args[0][1]
    assert params[0] == "a"
    assert params[1] is True  # is_enabled padrao
    assert isinstance(params[2], Json)


def test_criar_regra_duplicada_retorna_409(client, auth_ok, cursor):
    cursor.execute.side_effect = psycopg2.IntegrityError()
    assert client.post("/rules", json={"flag_name": "a", "rules": REGRA}, headers=AUTH).status_code == 409


def test_buscar_regra(client, auth_ok, cursor):
    cursor.fetchone.return_value = {"flag_name": "a", "rules": REGRA, "is_enabled": True}
    resp = client.get("/rules/a", headers=AUTH)
    assert resp.status_code == 200
    assert resp.get_json()["rules"] == REGRA


def test_buscar_regra_inexistente_retorna_404(client, auth_ok, cursor):
    cursor.fetchone.return_value = None
    assert client.get("/rules/x", headers=AUTH).status_code == 404


def test_atualizar_sem_campos_retorna_400(client, auth_ok):
    assert client.put("/rules/a", json={"x": 1}, headers=AUTH).status_code == 400


def test_atualizar_regra_inexistente_retorna_404(client, auth_ok, cursor):
    cursor.rowcount = 0
    assert client.put("/rules/a", json={"is_enabled": False}, headers=AUTH).status_code == 404


def test_deletar_regra(client, auth_ok, cursor):
    cursor.rowcount = 1
    assert client.delete("/rules/a", headers=AUTH).status_code == 204
