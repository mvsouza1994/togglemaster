"""Testes unitarios do analytics-service (sem SQS e DynamoDB reais)."""
import json
from unittest import mock

import pytest
from botocore.exceptions import ClientError

import app as app_module

EVENTO = {"user_id": "u1", "flag_name": "nova-ui", "result": True, "timestamp": "2026-10-18T12:00:00Z"}


@pytest.fixture
def aws():
    """Troca os clientes SQS/DynamoDB por mocks a cada teste."""
    with mock.patch.object(app_module, "sqs_client") as sqs, \
            mock.patch.object(app_module, "dynamodb_client") as dynamo:
        yield sqs, dynamo


def mensagem(body):
    return {"MessageId": "m1", "ReceiptHandle": "rh1", "Body": body}


def test_health():
    resp = app_module.app.test_client().get("/health")
    assert resp.status_code == 200
    assert resp.get_json() == {"status": "ok"}


def test_mensagem_valida_grava_no_dynamo_e_apaga_da_fila(aws):
    sqs, dynamo = aws
    app_module.process_message(mensagem(json.dumps(EVENTO)))

    item = dynamo.put_item.call_args.kwargs["Item"]
    assert dynamo.put_item.call_args.kwargs["TableName"] == "ToggleMasterAnalyticsTeste"
    assert item["user_id"] == {"S": "u1"}
    assert item["flag_name"] == {"S": "nova-ui"}
    assert item["result"] == {"BOOL": True}
    assert "S" in item["event_id"]
    sqs.delete_message.assert_called_once_with(QueueUrl=app_module.SQS_QUEUE_URL, ReceiptHandle="rh1")


def test_json_invalido_nao_apaga_mensagem(aws):
    sqs, dynamo = aws
    app_module.process_message(mensagem("isso nao e json"))
    dynamo.put_item.assert_not_called()
    sqs.delete_message.assert_not_called()


def test_erro_no_dynamo_mantem_mensagem_para_retentativa(aws):
    sqs, dynamo = aws
    dynamo.put_item.side_effect = ClientError({"Error": {"Code": "500", "Message": "falha"}}, "PutItem")
    app_module.process_message(mensagem(json.dumps(EVENTO)))
    sqs.delete_message.assert_not_called()


def test_evento_sem_campo_obrigatorio_nao_apaga_mensagem(aws):
    sqs, dynamo = aws
    app_module.process_message(mensagem(json.dumps({"user_id": "u1"})))
    dynamo.put_item.assert_not_called()
    sqs.delete_message.assert_not_called()
