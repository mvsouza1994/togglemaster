#!/bin/bash
# Gera k8s/secrets.yaml com todos os valores em base64 (exigencia do enunciado).
# Os endpoints sao lidos da AWS na hora -> nada fica hardcoded no repositorio.
#
# Uso:  ./scripts/gen-secrets.sh <SERVICE_API_KEY>
#
# NOTA: nenhuma credencial da AWS (access key / session token) entra aqui.
# Os pods herdam a LabRole do no via IMDS.
set -euo pipefail

SERVICE_API_KEY="${1:-PREENCHER}"
MASTER_KEY="${MASTER_KEY:-tm-master-2f8a41d7c9be4a15}"
DB_PASS="${DB_PASS:-ToggleMaster2026Lab}"
REGION=us-east-1

b64() { printf '%s' "$1" | base64 -w 0; }

ep() { aws rds describe-db-instances --db-instance-identifier "$1" \
        --query "DBInstances[0].Endpoint.Address" --output text; }

AUTH_EP=$(ep auth-db)
FLAGS_EP=$(ep flags-db)
TARGETING_EP=$(ep targeting-db)
REDIS_EP=$(aws elasticache describe-cache-clusters --cache-cluster-id togglemaster-redis \
            --show-cache-node-info --query "CacheClusters[0].CacheNodes[0].Endpoint.Address" --output text)
SQS_URL=$(aws sqs get-queue-url --queue-name togglemaster-events --query QueueUrl --output text)

cat > "$(dirname "$0")/../k8s/secrets.yaml" <<EOF
# GERADO POR scripts/gen-secrets.sh - nao editar a mao
apiVersion: v1
kind: Secret
metadata:
  name: auth-secrets
  namespace: auth
type: Opaque
data:
  DATABASE_URL: $(b64 "postgres://postgres:${DB_PASS}@${AUTH_EP}:5432/auth_db?sslmode=require")
  MASTER_KEY: $(b64 "${MASTER_KEY}")
---
apiVersion: v1
kind: Secret
metadata:
  name: flag-secrets
  namespace: flags
type: Opaque
data:
  DATABASE_URL: $(b64 "postgres://postgres:${DB_PASS}@${FLAGS_EP}:5432/flags_db?sslmode=require")
---
apiVersion: v1
kind: Secret
metadata:
  name: targeting-secrets
  namespace: targeting
type: Opaque
data:
  DATABASE_URL: $(b64 "postgres://postgres:${DB_PASS}@${TARGETING_EP}:5432/targeting_db?sslmode=require")
---
apiVersion: v1
kind: Secret
metadata:
  name: evaluation-secrets
  namespace: evaluation
type: Opaque
data:
  REDIS_URL: $(b64 "redis://${REDIS_EP}:6379")
  SERVICE_API_KEY: $(b64 "${SERVICE_API_KEY}")
  AWS_SQS_URL: $(b64 "${SQS_URL}")
---
apiVersion: v1
kind: Secret
metadata:
  name: analytics-secrets
  namespace: analytics
type: Opaque
data:
  AWS_SQS_URL: $(b64 "${SQS_URL}")
EOF

echo "k8s/secrets.yaml gerado."
echo "  auth-db      = ${AUTH_EP}"
echo "  flags-db     = ${FLAGS_EP}"
echo "  targeting-db = ${TARGETING_EP}"
echo "  redis        = ${REDIS_EP}"
