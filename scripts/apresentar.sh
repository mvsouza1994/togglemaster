#!/bin/bash
# CONDUZ A APRESENTACAO INTEIRA.
#
# Voce roda UM comando e aperta Enter entre os blocos. O script mostra na tela
# a fala de cada bloco (para voce ler em voz alta) e executa os comandos sozinho.
#
#   bash scripts/apresentar.sh
#
# Cobre os blocos B, D, E, F e G do roteiro. Os blocos A, C, H e I sao falados
# (diagrama / console AWS / camera) e o script so avisa a hora de trocar de tela.
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="/c/Program Files/Amazon/AWSCLIV2:$PATH"

# Descobre a URL do NLB e a SERVICE_API_KEY lendo do proprio cluster.
# Precisa ser dinamico: o deploy.sh gera uma chave NOVA a cada execucao, e o NLB
# muda se o ingress-nginx for recriado. Nada hardcoded aqui envelhece.
NLB="${NLB:-$(kubectl get svc -n ingress-nginx ingress-nginx-controller       -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)}"
KEY="${KEY:-$(kubectl get secret evaluation-secrets -n evaluation       -o jsonpath='{.data.SERVICE_API_KEY}' 2>/dev/null | base64 -d)}"

if [ -z "$NLB" ] || [ -z "$KEY" ]; then
  echo ""
  echo "  Nao achei o NLB ou a chave no cluster."
  echo "  Os 5 servicos ja foram implantados? Rode primeiro:"
  echo "      bash scripts/deploy.sh"
  echo ""
  exit 1
fi
LOCAL_KEY=$(grep '^SERVICE_API_KEY=' .env 2>/dev/null | cut -d= -f2)

# ---------- aparencia ----------
B=$'\e[1m'; D=$'\e[2m'; R=$'\e[0m'
CY=$'\e[36m'; YL=$'\e[33m'; GR=$'\e[32m'; MG=$'\e[35m'

bloco() {  # bloco <letra> <tempo> <titulo>
  echo ""; echo ""
  echo "${CY}${B}════════════════════════════════════════════════════════════════════${R}"
  echo "${CY}${B}  BLOCO $1${R}  ${D}·  $2${R}"
  echo "${CY}${B}  $3${R}"
  echo "${CY}${B}════════════════════════════════════════════════════════════════════${R}"
}

fala() {  # fala <texto...>
  echo ""
  echo "${YL}${B}  ╭─ FALE ISTO ────────────────────────────────────────────────────${R}"
  while IFS= read -r linha; do
    echo "${YL}  │${R}  $linha"
  done <<< "$1"
  echo "${YL}${B}  ╰────────────────────────────────────────────────────────────────${R}"
}

pausa() {
  echo ""
  read -rp "  ${D}[Enter para executar]${R} " _
  echo ""
}

roda() {  # roda <comando...>
  echo "${GR}  \$ $*${R}"
  echo ""
  "$@"
  echo ""
}

roda_sh() {  # roda_sh <string de shell>  (quando precisa de pipe/aspas)
  echo "${GR}  \$ $1${R}"
  echo ""
  eval "$1"
  echo ""
}

espera_tela() {
  echo ""
  read -rp "  ${MG}>> $1  [Enter quando voltar]${R} " _
}

clear
echo ""
echo "${B}  ToggleMaster — Tech Challenge Fase 2${R}"
echo "  ${D}apresentacao conduzida · aperte Enter para avancar${R}"
echo ""
echo "  NLB:  ${D}$NLB${R}"
echo "  Lab:  ${D}expira 20:12 BRT${R}"
pausa

# ════════════════════════════════════════════════════════════════════
bloco A "0:00 – 2:30" "Arquitetura e os 3 data stores"
echo "  ${D}Sem terminal. Mostre o diagrama do README.md e fale.${R}"
fala "O ToggleMaster era um monolito na Fase 1. Aqui ele virou 5 microsservicos:
auth e evaluation em Go, flag, targeting e analytics em Python.
O fluxo quente: a aplicacao chama /evaluate; o evaluation-service consulta o
flag-service e o targeting-service, decide true ou false, devolve a resposta e
publica um evento no SQS. O analytics-service consome a fila e grava no DynamoDB.

Os 3 data stores, que o enunciado cobra explicitamente:

RDS PostgreSQL guarda a fonte de verdade: definicoes das flags, regras de
segmentacao e chaves de API. Dado relacional e transacional, precisa de
consistencia forte. Sao 3 instancias independentes — cada microsservico e dono
do proprio banco.

ElastiCache Redis existe por causa da latencia. O /evaluate e o hot path, chamado
a cada request. Sem cache, cada avaliacao viraria duas chamadas HTTP mais duas
queries SQL. O dado e efemero e reconstruivel: se o cache cair, o sistema continua
correto, so fica mais lento.

DynamoDB e para volume de escrita. Os eventos sao append-only, nunca atualizados,
consultados por chave — nao precisam de JOIN. No teste de carga foram mais de 39
mil eventos em poucos minutos. Um db.t3.micro nao aguentaria; o DynamoDB
on-demand escala sozinho."
espera_tela "Troque para a janela do terminal"

# ════════════════════════════════════════════════════════════════════
bloco B "2:30 – 4:30" "Ambiente local — os 9 conteineres"
fala "Sao 9 conteineres: os 5 microsservicos mais 4 data stores — duas instancias
PostgreSQL, um Redis e o DynamoDB Local, exatamente como o enunciado pede."
pausa
roda docker compose ps

fala "Os cinco servicos respondendo no health check."
pausa
for p in 8001 8002 8003 8004 8005; do
  printf "  porta %s -> " "$p"; curl -s -m 5 "http://localhost:$p/health" || echo "(sem resposta)"; echo
done
echo ""

fala "A flag e a regra de rollout de 50 por cento ja estao criadas. Repare agora:
usuarios diferentes recebem resultados diferentes. E o targeting-service
aplicando o percentual. E ao repetir o mesmo usuario, a resposta vem do cache."
pausa
echo "${GR}  \$ curl \"http://localhost:8004/evaluate?user_id=<N>&flag_name=enable-new-dashboard\"${R}"
echo ""
for u in user-123 user-456 user-789 user-abc; do
  printf "  %-10s -> " "$u"
  curl -s -m 8 "http://localhost:8004/evaluate?user_id=$u&flag_name=enable-new-dashboard"; echo
done
echo ""
printf "  %-10s -> " "user-123"
curl -s -m 8 "http://localhost:8004/evaluate?user_id=user-123&flag_name=enable-new-dashboard"; echo
echo ""

fala "No log do evaluation aparece o Cache MISS na primeira consulta e o Cache HIT
nas seguintes — e o evento sendo publicado no SQS."
pausa
roda_sh "docker compose logs --tail 40 evaluation-service 2>&1 | grep -iE 'cache|sqs' | tail -6"

fala "E aqui os eventos gravados no DynamoDB Local."
pausa
roda_sh "aws dynamodb scan --table-name ToggleMasterAnalytics --endpoint-url http://localhost:8000 --select COUNT --query Count --output text"

echo "  ${D}Se perguntarem por que 2 PostgreSQL para 3 bancos: o enunciado fixa 2${R}"
echo "  ${D}instancias locais. Na nuvem sao 3 RDS separados, como pedido.${R}"

# ════════════════════════════════════════════════════════════════════
bloco C "4:30 – 6:30" "Console AWS — a infraestrutura provisionada"
echo "  ${D}Passe pelas 6 abas do navegador, ~20 s cada:${R}"
echo ""
echo "    1. EKS -> Computacao ...... node group, min 1 / desejado 2 / max 4"
echo "    2. ECR .................... os 5 repositorios, tag v1"
echo "    3. RDS .................... as 3 instancias available"
echo "    4. ElastiCache ............ togglemaster-redis, cache.t3.micro"
echo "    5. SQS .................... togglemaster-events, tipo Standard"
echo "    6. DynamoDB ............... ToggleMasterAnalytics, chave event_id"
fala "Todo o provisionamento usou a LabRole — tanto a cluster role quanto a node role.
No AWS Academy nao e possivel criar IAM roles, entao essa role existente e
passada explicitamente em cada recurso que precisa de permissao."
espera_tela "Volte para o terminal"

# ════════════════════════════════════════════════════════════════════
bloco D "6:30 – 8:00" "Os 5 microsservicos como Pods"
fala "O cluster tem dois nos t3.medium, criados pelo managed node group."
pausa
roda kubectl get nodes

fala "Cada aplicacao tem o proprio namespace, como o enunciado pede: auth, flags,
targeting, evaluation e analytics."
pausa
roda_sh "kubectl get pods -A -o wide 2>&1 | grep -vE 'kube-system|ingress-nginx'"

fala "Todos os Deployments tem requests e limits de CPU e memoria — o request de CPU
e justamente a base de calculo do HPA — e readiness e liveness probe apontando
para /health. Os Services sao ClusterIP; quem expoe para fora e o Ingress."
pausa
roda_sh "kubectl get deploy,svc -A 2>&1 | grep -vE 'kube-system|ingress-nginx'"

fala "E aqui o Network Load Balancer que o Nginx Ingress Controller provisionou na AWS."
pausa
roda kubectl get svc -n ingress-nginx ingress-nginx-controller

# ════════════════════════════════════════════════════════════════════
bloco E "8:00 – 10:00" "Ingress funcionando — curl no Load Balancer"
fala "Essas chamadas vao para o DNS do Network Load Balancer. O roteamento por path e
do Ingress: /flags vai para o flag-service, /rules para o targeting-service,
/evaluate para o evaluation-service."
pausa
echo "${GR}  \$ curl http://\$NLB/auth/health${R}"
printf "  -> "; curl -s -m 15 "http://$NLB/auth/health"; echo; echo

echo "${GR}  \$ curl http://\$NLB/flags -H \"Authorization: Bearer \$KEY\"${R}"
printf "  -> "; curl -s -m 15 "http://$NLB/flags" -H "Authorization: Bearer $KEY" | head -c 220; echo; echo

fala "E a avaliacao pela URL publica, com o mesmo rollout de 50 por cento."
pausa
echo "${GR}  \$ curl \"http://\$NLB/evaluate?user_id=<N>&flag_name=enable-new-dashboard\"${R}"
echo ""
for u in user-123 user-456 user-789 user-abc user-def user-ghi; do
  printf "  %-10s -> " "$u"
  curl -s -m 15 "http://$NLB/evaluate?user_id=$u&flag_name=enable-new-dashboard"; echo
done
echo ""

# ════════════════════════════════════════════════════════════════════
bloco F "10:00 – 13:30" "Carga no evaluation-service e o HPA escalando"
echo "  ${D}Estado inicial dos HPAs (devem estar em 1 replica):${R}"
echo ""
kubectl get hpa -A
fala "Vou gerar carga contra o /evaluate. O HPA esta configurado para 70 por cento de
utilizacao media de CPU, minimo 1 e maximo 5 replicas. Repare na coluna TARGETS:
quando a CPU passa de 70 por cento, o controlador comeca a adicionar pods.
O HPA leva de 30 a 90 segundos para reagir — o metrics-server coleta a cada 15."
pausa

echo "${GR}  \$ kubectl apply -f k8s/08-loadgen.yaml${R}"
kubectl apply -f k8s/08-loadgen.yaml
echo ""
echo "${GR}  \$ python scripts/carga.py \"http://\$NLB/evaluate?...\" -c 50 -z 170  ${D}(em segundo plano)${R}"
python scripts/carga.py "http://$NLB/evaluate?user_id=u1&flag_name=enable-new-dashboard" -c 50 -z 170 > /tmp/carga-demo.log 2>&1 &
CARGA_PID=$!
echo ""
echo "  ${D}acompanhando o HPA — 12 amostras de 15 s (3 minutos)${R}"
echo ""
printf "  %-9s  %-22s  %-22s\n" "hora" "evaluation" "analytics"
printf "  %-9s  %-22s  %-22s\n" "─────────" "──────────────────────────────" "──────────────────────────────"
for i in $(seq 1 12); do
  EV=$(kubectl get hpa evaluation-hpa -n evaluation --no-headers 2>/dev/null | awk '{print $3" "$4"  ->  "$7" replicas"}')
  AN=$(kubectl get hpa analytics-hpa  -n analytics  --no-headers 2>/dev/null | awk '{print $3" "$4"  ->  "$7" replicas"}')
  printf "  %-9s  %-22s  %-22s\n" "$(date +%H:%M:%S)" "${EV:-...}" "${AN:-...}"
  sleep 15
done
echo ""
fala "Os dois HPAs subiram. O evaluation foi de 1 para 4 replicas e o analytics de 1
para 5, que e o maximo configurado. Repare que o analytics escalou sozinho, so
por causa dos eventos que a carga gerou na fila."
pausa
roda_sh "kubectl get pods -n evaluation --no-headers 2>&1 | grep -v loadgen"
roda kubectl get pods -n analytics

echo "  ${D}derrubando o gerador de carga...${R}"
kubectl delete -f k8s/08-loadgen.yaml >/dev/null 2>&1
wait $CARGA_PID 2>/dev/null
echo ""
echo "  ${D}resumo da carga:${R}"
tail -6 /tmp/carga-demo.log 2>/dev/null

# ════════════════════════════════════════════════════════════════════
bloco G "13:30 – 16:00" "SQS manual, analytics escalando e DynamoDB"
fala "Alem da carga HTTP, o enunciado pede o envio manual de mensagens para o SQS.
Vou publicar 2000 mensagens em lotes de 10, direto pela API da fila, sem passar
pelo evaluation-service."
pausa
roda bash scripts/enviar-sqs.sh 2000

fala "O analytics-service consome essa fila. Quanto mais mensagens chegam, mais o
worker trabalha, mais CPU consome — e o HPA adiciona replicas."
pausa
roda kubectl get hpa -n analytics
roda kubectl get pods -n analytics

fala "E aqui o caminho completo fechado: evento publicado no SQS, consumido pelo
analytics-service, gravado no DynamoDB."
pausa
roda_sh "kubectl logs -n analytics deploy/analytics-service --tail 30 2>&1 | grep -i salvo | tail -5"
echo "  ${D}total de eventos na tabela:${R}"
roda_sh "aws dynamodb scan --table-name ToggleMasterAnalytics --select COUNT --output text | awk '{s+=\$1} END {print \"  \"s\" eventos\"}'"
espera_tela "Abra o console DynamoDB -> Explorar itens da tabela -> Executar e mostre os itens"

# ════════════════════════════════════════════════════════════════════
bloco H "16:00 – 19:00" "Desafios e justificativa da escalabilidade"
echo "  ${D}Sem terminal. Fale olhando para a camera — 4 pontos, ~45 s cada.${R}"
fala "1 — O codigo-fonte nao compilava.
O primeiro desafio veio antes da infraestrutura. Foram 6 defeitos corrigidos. O
mais sutil estava no auth-service: o driver pgx/stdlib era importado
normalmente, mas ele existe so pelo efeito colateral do init, que registra o
driver no database/sql. Em Go, import nao usado e erro de compilacao — e se
alguem corrigisse apagando o import, viraria um erro de runtime bem pior de
diagnosticar: unknown driver pgx. O certo e o import em branco, com underscore."
pausa
fala "2 — Limitacoes da LabRole.
O AWS Academy nao permite criar IAM roles. Isso elimina de saida o eksctl create
cluster, o KEDA, o Karpenter e o IRSA. Tudo foi provisionado passando a LabRole
existente explicitamente, tanto no cluster quanto no node group."
pausa
fala "3 — O IMDS hop limit, o desafio mais interessante.
O plano era os pods herdarem a LabRole do no via IMDS, sem credencial nenhuma
dentro do cluster. Na pratica, analytics e evaluation retornavam Unable to
locate credentials. A causa: o managed node group sobe as instancias com hop
limit 1 no metadata service. Um pod esta a 2 hops do 169.254.169.254, entao o
pacote e descartado — e uma protecao deliberada do EKS para impedir que pods
assumam a role do no. Havia duas saidas: subir o hop limit para 2, o que
enfraquece esse isolamento, ou injetar as credenciais temporarias do lab como
Secret. Escolhemos a segunda. O custo e honesto: as credenciais expiram em cerca
de 4 horas e precisam ser renovadas. Em producao o certo seria IRSA ou EKS Pod
Identity."
pausa
fala "4 — Por que HPA por CPU e nao KEDA.
Para o analytics-service, KEDA seria tecnicamente superior: escalaria pelo
queueDepth do SQS, que e o sinal direto do trabalho pendente, e escalaria de
zero a N. Mas KEDA depende de IRSA, que depende de criar uma IAM role —
bloqueado no Academy. O workaround adotado e indireto e funciona: a fila enche,
o worker processa mais mensagens, a CPU sobe, o HPA adiciona replicas. O teste
comprovou o encadeamento — a carga no evaluation gerou eventos suficientes para
levar o analytics de 1 a 5 replicas sozinho. As limitacoes a gente reconhece:
CPU e um proxy indireto. Se o consumo fosse limitado por I/O em vez de CPU, o
sinal seria fraco e o autoscaling reagiria mal. E nao ha escala a zero."
pausa

# ════════════════════════════════════════════════════════════════════
bloco I "19:00 – 20:00" "Fechamento"
fala "Recapitulando: 5 microsservicos conteinerizados com build multi-stage,
infraestrutura provisionada na AWS com EKS, ECR, 3 RDS, ElastiCache, DynamoDB e
SQS, implantados com namespaces separados, probes, secrets em base64, requests e
limits, expostos por Nginx Ingress, e escalando automaticamente por HPA de CPU
nos dois servicos exigidos. Os recursos serao destruidos logo apos esta gravacao
para nao consumir o orcamento do laboratorio. Obrigado."

echo ""
echo ""
echo "${CY}${B}════════════════════════════════════════════════════════════════════${R}"
echo "${B}  FIM DA APRESENTACAO${R}"
echo ""
echo "  ${YL}Depois de parar a gravacao, nao esqueca:${R}"
echo "  ${GR}\$ bash scripts/teardown.sh${R}"
echo "${CY}${B}════════════════════════════════════════════════════════════════════${R}"
echo ""
