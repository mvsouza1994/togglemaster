#!/bin/bash
# Copia as credenciais do AWS Academy de um perfil do ~/.aws/credentials para os
# secrets do repositorio no GitHub (usados pelos workflows). Nada e impresso na tela.
#
# Uso (a cada Start Lab, depois de colar o bloco "AWS CLI" no [default]):
#   bash scripts/gh-aws-secrets.sh            # perfil default
#   bash scripts/gh-aws-secrets.sh outro-perfil
set -euo pipefail
PROFILE="${1:-default}"

echo -n "conta do perfil '$PROFILE': "
aws sts get-caller-identity --profile "$PROFILE" --query Account --output text

for k in aws_access_key_id aws_secret_access_key aws_session_token; do
  v=$(aws configure get "$k" --profile "$PROFILE")
  [ -n "$v" ] || { echo "ERRO: '$k' vazio no perfil $PROFILE"; exit 1; }
  printf '%s' "$v" | gh secret set "$(echo "$k" | tr '[:lower:]' '[:upper:]')"
done
unset v
echo "secrets AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY e AWS_SESSION_TOKEN atualizados"
