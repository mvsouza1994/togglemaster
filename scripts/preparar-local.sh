#!/bin/bash
# Deixa o ambiente local pronto para gravar. Rode UMA VEZ antes de ligar a camera.
#   - sobe os 9 conteineres
#   - cria a tabela no DynamoDB Local (o container e -inMemory, some a cada subida)
#   - cria uma SERVICE_API_KEY nova no auth-service e injeta no evaluation
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="/c/Program Files/Amazon/AWSCLIV2:$PATH"
source .env

echo "===== 1. Subindo os 9 conteineres ====="
docker compose up -d --build
echo "aguardando os healthchecks..."
for i in $(seq 1 60); do
  ok=$(docker compose ps --format '{{.Status}}' | grep -c "healthy")
  printf "\r  saudaveis: %s/8" "$ok"
  [ "$ok" -ge 8 ] && break
  sleep 5
done
echo ""

echo "===== 2. Tabela no DynamoDB Local ====="
aws dynamodb create-table --table-name ToggleMasterAnalytics \
  --attribute-definitions AttributeName=event_id,AttributeType=S \
  --key-schema AttributeName=event_id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST --endpoint-url http://localhost:8000 \
  --query "TableDescription.TableStatus" --output text 2>/dev/null \
  || echo "tabela ja existe"

echo "===== 3. SERVICE_API_KEY nova ====="
KEY=$(curl -s -X POST http://localhost:8001/admin/keys \
  -H "Authorization: Bearer $MASTER_KEY" -H "Content-Type: application/json" \
  -d '{"name":"servico-interno"}' | python -c "import sys,json;print(json.load(sys.stdin)['key'])")
if [ -z "$KEY" ]; then echo "ERRO: nao consegui criar a chave"; exit 1; fi
echo "chave: ${KEY:0:14}..."

sed -i "s|^SERVICE_API_KEY=.*|SERVICE_API_KEY=$KEY|" .env
docker compose up -d evaluation-service
sleep 8

echo "===== 4. Aquecendo o fluxo (para o video ja ter dados) ====="
curl -s -X POST http://localhost:8002/flags -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d '{"name":"enable-new-dashboard","description":"Novo dashboard","is_enabled":true}' >/dev/null
curl -s -X POST http://localhost:8003/rules -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d '{"flag_name":"enable-new-dashboard","is_enabled":true,"rules":{"type":"PERCENTAGE","value":50}}' >/dev/null
curl -s "http://localhost:8004/evaluate?user_id=aquecimento&flag_name=enable-new-dashboard" >/dev/null

echo ""
echo "===== PRONTO PARA GRAVAR ====="
docker compose ps --format "table {{.Name}}\t{{.Status}}"
echo ""
echo "Na gravacao rode:  bash scripts/demo-local.sh"
