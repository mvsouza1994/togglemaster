#!/bin/bash
# FALLBACK do AWS Academy: injeta as credenciais temporarias do lab como Secret.
#
# Por que existe: no EKS os pods deveriam herdar a LabRole do no via IMDS, mas o
# managed node group sobe as instancias com HttpPutResponseHopLimit=1 e o pod fica
# a 2 hops do metadata service -> "Unable to locate credentials". A correcao limpa
# seria subir o hop limit para 2 (ec2 modify-instance-metadata-options); este script
# e a alternativa quando essa alteracao nao esta disponivel.
#
# ATENCAO: as credenciais do Learner Lab expiram a cada sessao (~4h).
# Rode este script de novo (e reinicie os deployments) a cada 'Start Lab'.
#
# Os valores NUNCA sao impressos: vao do arquivo direto para o kubectl.
set -euo pipefail

CRED_FILE="${AWS_CREDENTIALS_FILE:-$HOME/.aws/credentials}"
[ -f "$CRED_FILE" ] || { echo "ERRO: $CRED_FILE nao encontrado"; exit 1; }

val() { grep -m1 "^$1" "$CRED_FILE" | cut -d= -f2- | tr -d ' \r'; }

AK=$(val aws_access_key_id)
SK=$(val aws_secret_access_key)
ST=$(val aws_session_token)

[ -n "$AK" ] && [ -n "$SK" ] && [ -n "$ST" ] || { echo "ERRO: credenciais incompletas em $CRED_FILE"; exit 1; }

for ns in evaluation analytics; do
  kubectl create secret generic aws-creds -n "$ns" \
    --from-literal=AWS_ACCESS_KEY_ID="$AK" \
    --from-literal=AWS_SECRET_ACCESS_KEY="$SK" \
    --from-literal=AWS_SESSION_TOKEN="$ST" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  echo "secret/aws-creds aplicado no namespace $ns"
done

echo "OK (valores armazenados em base64 pelo proprio kubectl, nada impresso aqui)"
