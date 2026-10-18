#!/bin/bash
# DEMO PARA O VIDEO - Etapa 1: ambiente local (9 conteineres) + fluxo E2E.
# Mostra cada comando na tela ANTES de executar, para a camera acompanhar.
#
# Rode 'bash scripts/preparar-local.sh' UMA VEZ antes de gravar.
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="/c/Program Files/Amazon/AWSCLIV2:$PATH"
source .env

AZ='\033[1;36m'; VD='\033[1;32m'; NC='\033[0m'
titulo() { echo ""; echo -e "${VD}=============================================================${NC}"; echo -e "${VD} $1${NC}"; echo -e "${VD}=============================================================${NC}"; }
rodar()  { echo ""; echo -e "${AZ}\$ $1${NC}"; sleep 1; eval "$1"; }
pausa()  { echo ""; read -rp "  [Enter para continuar] "; }

titulo "1. OS 9 CONTEINERES (5 microsservicos + 4 data stores)"
rodar 'docker compose ps --format "table {{.Name}}\t{{.Service}}\t{{.Status}}"'
rodar 'docker compose ps -q | wc -l'
pausa

titulo "2. HEALTH CHECK DOS 5 MICROSSERVICOS"
for p in 8001:auth 8002:flag 8003:targeting 8004:evaluation 8005:analytics; do
  echo -e "${AZ}\$ curl -s http://localhost:${p%%:*}/health${NC}   (${p##*:}-service)"
  curl -s --max-time 5 "http://localhost:${p%%:*}/health"; echo ""
done
pausa

titulo "3. CRIAR UMA FEATURE FLAG (flag-service -> PostgreSQL)"
rodar "curl -s -X POST http://localhost:8002/flags \
  -H 'Authorization: Bearer \$SERVICE_API_KEY' -H 'Content-Type: application/json' \
  -d '{\"name\":\"enable-new-dashboard\",\"description\":\"Novo dashboard\",\"is_enabled\":true}'"
pausa

titulo "4. CRIAR REGRA DE SEGMENTACAO DE 50% (targeting-service -> PostgreSQL)"
rodar "curl -s -X POST http://localhost:8003/rules \
  -H 'Authorization: Bearer \$SERVICE_API_KEY' -H 'Content-Type: application/json' \
  -d '{\"flag_name\":\"enable-new-dashboard\",\"is_enabled\":true,\"rules\":{\"type\":\"PERCENTAGE\",\"value\":50}}'"
pausa

titulo "5. AVALIAR A FLAG (evaluation-service: hot path, Redis + SQS)"
echo "  Usuarios diferentes caem em lados diferentes do rollout de 50%:"
for u in user-123 user-456 user-789 user-abc; do
  echo -e "${AZ}\$ curl -s 'http://localhost:8004/evaluate?user_id=$u&flag_name=enable-new-dashboard'${NC}"
  curl -s --max-time 5 "http://localhost:8004/evaluate?user_id=$u&flag_name=enable-new-dashboard"; echo ""
done
echo ""
echo "  Repetindo o mesmo usuario -> agora vem do CACHE (Redis):"
rodar "curl -s 'http://localhost:8004/evaluate?user_id=user-123&flag_name=enable-new-dashboard'"
pausa

titulo "6. PROVA DO CACHE REDIS NO LOG DO EVALUATION-SERVICE"
rodar "docker compose logs evaluation-service --tail 40 | grep -iE 'cache|sqs' | tail -12"
pausa

titulo "7. O ANALYTICS CONSUMIU DO SQS E GRAVOU NO DYNAMODB LOCAL"
rodar "docker compose logs analytics-service --tail 15"
rodar "aws dynamodb scan --table-name ToggleMasterAnalytics --endpoint-url http://localhost:8000 --select COUNT --output table"
echo ""
echo "  Alguns itens gravados:"
rodar "aws dynamodb scan --table-name ToggleMasterAnalytics --endpoint-url http://localhost:8000 --max-items 3 --query 'Items[].{user:user_id.S,flag:flag_name.S,resultado:result.BOOL}' --output table"

titulo "FIM DA DEMO LOCAL"
