#!/bin/bash
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
