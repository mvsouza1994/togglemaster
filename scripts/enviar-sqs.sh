#!/bin/bash
# Envia mensagens MANUALMENTE para a fila SQS.
#
# O PDF (pag. 9) pede explicitamente: "Envie manualmente varias mensagens para a
# fila SQS" e depois "Mostre o HPA do analytics-service detectando a carga".
# Este script cobre esse item — e independe do evaluation-service.
#
# Uso:  bash scripts/enviar-sqs.sh [QUANTIDADE]     (padrao: 500)
set -uo pipefail
export PATH="/c/Program Files/Amazon/AWSCLIV2:$PATH"

TOTAL="${1:-500}"
REGION=us-east-1
QURL=$(aws sqs get-queue-url --queue-name togglemaster-events --region $REGION --query QueueUrl --output text)
echo "fila:  $QURL"
echo "envio: $TOTAL mensagens (lotes de 10)"

# O analytics-service espera um Body JSON com: user_id, flag_name, result, timestamp
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
enviadas=0
lote=$(( (TOTAL + 9) / 10 ))

for ((b=0; b<lote; b++)); do
  entries="["
  for ((i=0; i<10; i++)); do
    n=$(( b*10 + i ))
    [ $n -ge $TOTAL ] && break
    [ $i -gt 0 ] && entries+=","
    res=$( [ $((n % 2)) -eq 0 ] && echo true || echo false )
    body="{\"user_id\":\"manual-user-$n\",\"flag_name\":\"enable-new-dashboard\",\"result\":$res,\"timestamp\":\"$TS\"}"
    esc=$(printf '%s' "$body" | python -c "import sys,json;print(json.dumps(sys.stdin.read()))")
    entries+="{\"Id\":\"m$n\",\"MessageBody\":$esc}"
  done
  entries+="]"

  ok=$(aws sqs send-message-batch --queue-url "$QURL" --region $REGION \
        --entries "$entries" --query "length(Successful)" --output text 2>/dev/null)
  enviadas=$(( enviadas + ${ok:-0} ))
  printf "\r  enviadas: %d/%d" "$enviadas" "$TOTAL"
done
echo ""
echo ""
echo "profundidade da fila agora:"
aws sqs get-queue-attributes --queue-url "$QURL" --region $REGION \
  --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible \
  --query "Attributes" --output table
echo ""
echo "Acompanhe o analytics escalando:"
echo "  kubectl get hpa -n analytics -w"
echo "  kubectl get pods -n analytics -w"
