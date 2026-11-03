#!/bin/bash
set -uo pipefail
DEST="$HOME/.aws/credentials"
TMP=$(mktemp)

powershell.exe -NoProfile -Command "Get-Clipboard" 2>/dev/null | tr -d '\r' > "$TMP"

if ! grep -q '^\[default\]' "$TMP"; then
  echo "ERRO: o clipboard nao comeca com [default]. Copie o bloco inteiro do AWS CLI."
  rm -f "$TMP"; exit 1
fi
for k in aws_access_key_id aws_secret_access_key aws_session_token; do
  if ! grep -q "^$k" "$TMP"; then
    echo "ERRO: falta a linha '$k' no bloco copiado."
    rm -f "$TMP"; exit 1
  fi
done

[ -f "$DEST" ] && cp "$DEST" "$DEST.bak"
mv "$TMP" "$DEST"
echo "credenciais gravadas em $DEST (backup em $DEST.bak)"

export PATH="/c/Program Files/Amazon/AWSCLIV2:$PATH"
echo -n "validando: "
aws sts get-caller-identity --query "Account" --output text
