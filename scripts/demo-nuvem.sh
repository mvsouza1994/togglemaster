#!/bin/bash
# DEMO PARA O VIDEO - Etapa 2: cluster EKS, pods, ingress e fluxo E2E na nuvem.
# NLB e SERVICE_API_KEY sao descobertos em tempo de execucao (nada hardcoded).
set -uo pipefail
export PATH="/c/Program Files/Amazon/AWSCLIV2:$PATH"

AZ='\033[1;36m'; VD='\033[1;32m'; NC='\033[0m'
titulo() { echo ""; echo -e "${VD}=============================================================${NC}"; echo -e "${VD} $1${NC}"; echo -e "${VD}=============================================================${NC}"; }
rodar()  { echo ""; echo -e "${AZ}\$ $1${NC}"; sleep 1; eval "$1"; }
pausa()  { echo ""; read -rp "  [Enter para continuar] "; }

NLB=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
KEY=$(kubectl get secret evaluation-secrets -n evaluation -o jsonpath='{.data.SERVICE_API_KEY}' | base64 -d)

titulo "1. O CLUSTER EKS E SEUS NOS"
rodar "kubectl get nodes -o wide"
rodar "kubectl top nodes"
pausa

titulo "2. OS 5 MICROSSERVICOS COMO PODS, UM NAMESPACE CADA"
rodar "kubectl get pods -A -o wide | grep -E 'NAME|auth|flags|targeting|evaluation|analytics'"
rodar "kubectl get deploy,svc -n evaluation"
pausa

titulo "3. NGINX INGRESS CONTROLLER E O NLB PROVISIONADO NA AWS"
rodar "kubectl get svc -n ingress-nginx ingress-nginx-controller"
rodar "kubectl get ingress -A"
echo ""
echo -e "${VD}  URL publica: http://$NLB${NC}"
pausa

titulo "4. FLUXO E2E ATRAVES DO INGRESS (curl na URL do Load Balancer)"
rodar "curl -s http://$NLB/auth/health"
echo ""
echo "  Criando a feature flag via ingress -> flag-service -> RDS:"
rodar "curl -s -X POST http://$NLB/flags -H 'Authorization: Bearer $KEY' -H 'Content-Type: application/json' -d '{\"name\":\"enable-new-dashboard\",\"description\":\"Novo dashboard\",\"is_enabled\":true}'"
echo ""
echo "  Criando a regra de 50% -> targeting-service -> RDS:"
rodar "curl -s -X POST http://$NLB/rules -H 'Authorization: Bearer $KEY' -H 'Content-Type: application/json' -d '{\"flag_name\":\"enable-new-dashboard\",\"is_enabled\":true,\"rules\":{\"type\":\"PERCENTAGE\",\"value\":50}}'"
pausa

titulo "5. AVALIACAO (hot path: evaluation-service + ElastiCache + SQS)"
for u in user-123 user-456 user-789 user-abc; do
  echo -e "${AZ}\$ curl -s 'http://$NLB/evaluate?user_id=$u&flag_name=enable-new-dashboard'${NC}"
  curl -s --max-time 10 "http://$NLB/evaluate?user_id=$u&flag_name=enable-new-dashboard"; echo ""
done
echo ""
echo "  Mesmo usuario de novo -> CACHE HIT no ElastiCache:"
rodar "curl -s 'http://$NLB/evaluate?user_id=user-123&flag_name=enable-new-dashboard'"
pausa

titulo "6. O EVENTO PERCORREU O CAMINHO ATE O DYNAMODB"
rodar "kubectl logs -n evaluation deploy/evaluation-service --tail 15 | grep -iE 'cache|sqs' | tail -8"
rodar "kubectl logs -n analytics deploy/analytics-service --tail 12"
rodar "aws dynamodb scan --table-name ToggleMasterAnalytics --select COUNT --output table"

titulo "URL PARA USAR NA CARGA"
echo "  http://$NLB/evaluate?user_id=u1&flag_name=enable-new-dashboard"
