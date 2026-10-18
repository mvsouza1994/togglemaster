"""Fixtures dos testes: o app cria clientes boto3 e o worker SQS no import, entao tudo e mockado antes."""
import os
from unittest import mock

os.environ.setdefault("AWS_REGION", "us-east-1")
os.environ.setdefault("AWS_SQS_URL", "https://sqs.us-east-1.amazonaws.com/000000000000/teste")
os.environ.setdefault("AWS_DYNAMODB_TABLE", "ToggleMasterAnalyticsTeste")
os.environ["DISABLE_SQS_WORKER"] = "1"

# evita qualquer chamada real a AWS
_boto_patch = mock.patch("boto3.Session")
_boto_patch.start()
