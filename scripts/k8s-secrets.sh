#!/bin/bash
# Cria os Secrets dos 5 servicos no cluster a partir dos outputs do Terraform.
# Nada e gravado em arquivo: os valores vao direto do "terraform output" para o kubectl.
#
# Uso (depois do terraform apply e do update-kubeconfig):
#   bash scripts/k8s-secrets.sh
#
# MASTER_KEY e SERVICE_API_KEY: se ja existirem no cluster, sao mantidas;
# senao, sao geradas aqui. A SERVICE_API_KEY e semeada no banco do auth pelo
# Job de migracao (gitops/services/auth-service/db-migrate-job.yaml).
set -euo pipefail

cd "$(dirname "$0")/../terraform"

out() { terraform output -raw "$1"; }
db_url() { terraform output -json database_urls | python3 -c "import sys,json;print(json.load(sys.stdin)['$1'])"; }

# le um valor de um Secret existente (vazio se nao existir)
current() { kubectl get secret "$2" -n "$1" -o "jsonpath={.data.$3}" 2>/dev/null | base64 -d 2>/dev/null || true; }

MASTER_KEY="${MASTER_KEY:-$(current auth auth-secrets MASTER_KEY)}"
MASTER_KEY="${MASTER_KEY:-tm-master-$(openssl rand -hex 24)}"
SERVICE_API_KEY="${SERVICE_API_KEY:-$(current auth auth-secrets SERVICE_API_KEY)}"
SERVICE_API_KEY="${SERVICE_API_KEY:-tm_key_$(openssl rand -hex 32)}"

REDIS_URL=$(out redis_url)
SQS_URL=$(out sqs_queue_url)

apply_secret() { # namespace nome chave=valor...
  local ns=$1 name=$2; shift 2
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  local args=()
  for kv in "$@"; do args+=(--from-literal="$kv"); done
  kubectl create secret generic "$name" -n "$ns" "${args[@]}" --dry-run=client -o yaml | kubectl apply -f -
}

apply_secret auth auth-secrets \
  "DATABASE_URL=$(db_url auth)" "MASTER_KEY=$MASTER_KEY" "SERVICE_API_KEY=$SERVICE_API_KEY"
apply_secret flags flag-secrets "DATABASE_URL=$(db_url flags)"
apply_secret targeting targeting-secrets "DATABASE_URL=$(db_url targeting)"
apply_secret evaluation evaluation-secrets \
  "REDIS_URL=$REDIS_URL" "SERVICE_API_KEY=$SERVICE_API_KEY" "AWS_SQS_URL=$SQS_URL"
apply_secret analytics analytics-secrets "AWS_SQS_URL=$SQS_URL"

echo "Secrets criados. MASTER_KEY (guarde para usar o /admin/keys): ${MASTER_KEY:0:14}..."
