#!/bin/bash
# Implanta o ToggleMaster num cluster EKS ja provisionado (ver scripts/provision.sh).
# Cuida da ordem: auth-service primeiro, porque a SERVICE_API_KEY dos outros
# servicos e criada chamando o /admin/keys dele.
set -uo pipefail

cd "$(dirname "$0")/.."
MASTER_KEY="${MASTER_KEY:-tm-master-2f8a41d7c9be4a15}"

# O registro do ECR muda a cada conta do Learner Lab. Reescreve as imagens dos
# manifestos para a conta atual antes de aplicar, senao os pods ficam em
# ImagePullBackOff apontando para o ECR da conta anterior.
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
sed -i -E "s|[0-9]{12}\.dkr\.ecr\.|${ACCOUNT}.dkr.ecr.|g" k8s/0[1-5]-*.yaml
echo "imagens apontando para ${ACCOUNT}.dkr.ecr.us-east-1.amazonaws.com"

echo "===== 1. Complementos do cluster ====="
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.1/deploy/static/provider/aws/deploy.yaml

echo "===== 2. Namespaces ====="
kubectl apply -f k8s/00-namespaces.yaml

echo "===== 3. Schemas nos RDS (a partir de um pod, os bancos nao sao publicos) ====="
for pair in "auth-db:auth_db:auth-service" "flags-db:flags_db:flag-service" "targeting-db:targeting_db:targeting-service"; do
  ID="${pair%%:*}"; rest="${pair#*:}"; DB="${rest%%:*}"; SVC="${rest##*:}"
  EP=$(aws rds describe-db-instances --db-instance-identifier $ID --query "DBInstances[0].Endpoint.Address" --output text)
  echo "  $DB em $EP"
  kubectl run psql-$ID --rm -i --restart=Never --image=postgres:16-alpine \
    --env PGPASSWORD="${DB_PASS:-ToggleMaster2026Lab}" --env PGSSLMODE=require \
    --command -- psql -h $EP -U postgres -d $DB -v ON_ERROR_STOP=1 < $SVC/db/init.sql
done

echo "===== 4. Secrets (placeholder) + auth-service ====="
bash scripts/gen-secrets.sh "PENDENTE"
bash scripts/gen-aws-creds-secret.sh
kubectl apply -f k8s/secrets.yaml
kubectl apply -f k8s/01-auth.yaml
kubectl rollout status deployment/auth-service -n auth --timeout=300s

echo "===== 5. Criando a SERVICE_API_KEY ====="
KEY=$(kubectl run curl-key --rm -i --restart=Never --image=curlimages/curl:8.10.1 --quiet -- \
  -s -X POST http://auth-service.auth.svc.cluster.local:8001/admin/keys \
  -H "Authorization: Bearer $MASTER_KEY" -H "Content-Type: application/json" \
  -d '{"name":"servico-interno-eks"}' | python -c "import sys,json;print(json.load(sys.stdin)['key'])")
echo "chave criada: ${KEY:0:14}..."

echo "===== 6. Secrets definitivos + demais servicos ====="
bash scripts/gen-secrets.sh "$KEY"
kubectl apply -f k8s/secrets.yaml
kubectl apply -f k8s/02-flags.yaml -f k8s/03-targeting.yaml -f k8s/04-evaluation.yaml -f k8s/05-analytics.yaml
kubectl apply -f k8s/06-ingress.yaml -f k8s/07-hpa.yaml

for d in flags/flag-service targeting/targeting-service evaluation/evaluation-service analytics/analytics-service; do
  kubectl rollout status deployment/${d##*/} -n ${d%%/*} --timeout=300s
done

NLB=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo ""
echo "===== PRONTO ====="
echo "NLB:            http://$NLB"
echo "SERVICE_API_KEY $KEY"
echo ""
echo "Teste:"
echo "  curl -X POST http://$NLB/flags -H 'Authorization: Bearer $KEY' -H 'Content-Type: application/json' -d '{\"name\":\"enable-new-dashboard\",\"is_enabled\":true}'"
echo "  curl \"http://$NLB/evaluate?user_id=user-123&flag_name=enable-new-dashboard\""
