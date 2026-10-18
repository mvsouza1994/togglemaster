#!/bin/bash
# APRESENTACAO PELO AWS CLOUDSHELL — self-contained.
#
# Sobe UM arquivo para o CloudShell (Actions > Upload file) e roda:
#   bash apresentar-cloudshell.sh
#
# Faz tudo sozinho: instala o kubectl, configura o kubeconfig, descobre a URL do
# NLB e a API key lendo do proprio cluster, gera carga, envia ao SQS e le o
# DynamoDB. Nao depende de nenhum outro arquivo.
#
# NAO cobre o bloco B (os 9 conteineres do docker compose) — isso e impossivel
# no CloudShell, que roda na AWS e nao enxerga o Docker da sua maquina. Faca o
# bloco B antes, no Git Bash local, e depois venha para ca.
set -uo pipefail

REGION="${AWS_REGION:-us-east-1}"
CLUSTER="${CLUSTER:-togglemaster}"

# ---------- aparencia ----------
B=$'\e[1m'; D=$'\e[2m'; R=$'\e[0m'
CY=$'\e[36m'; YL=$'\e[33m'; GR=$'\e[32m'; MG=$'\e[35m'

bloco() {
  echo ""; echo ""
  echo "${CY}${B}════════════════════════════════════════════════════════════════════${R}"
  echo "${CY}${B}  BLOCO $1${R}  ${D}·  $2${R}"
  echo "${CY}${B}  $3${R}"
  echo "${CY}${B}════════════════════════════════════════════════════════════════════${R}"
}

fala() {
  echo ""
  echo "${YL}${B}  ╭─ FALE ISTO ────────────────────────────────────────────────────${R}"
  while IFS= read -r l; do echo "${YL}  │${R}  $l"; done <<< "$1"
  echo "${YL}${B}  ╰────────────────────────────────────────────────────────────────${R}"
}

console() {  # console <titulo> <passos separados por |>
  echo ""
  echo "${MG}${B}  ╭─ MOSTRE NO CONSOLE ────────────────────────────────────────────${R}"
  echo "${MG}  │${R}  ${B}$1${R}"
  echo "${MG}  │${R}"
  local n=1
  IFS='|' read -ra passos <<< "$2"
  for p in "${passos[@]}"; do
    echo "${MG}  │${R}  ${B}$n.${R} $p"
    n=$((n+1))
  done
  echo "${MG}${B}  ╰────────────────────────────────────────────────────────────────${R}"
  echo ""
  read -rp "  ${MG}[Enter quando terminar de mostrar]${R} " _
}

pausa() { echo ""; read -rp "  ${D}[Enter para executar]${R} " _; echo ""; }
roda()  { echo "${GR}  \$ $*${R}"; echo ""; "$@"; echo ""; }
roda_sh(){ echo "${GR}  \$ $1${R}"; echo ""; eval "$1"; echo ""; }

# ════════════════════════════════════════════════════════════════════
# PREPARO — rode isto ANTES de ligar a gravacao
# ════════════════════════════════════════════════════════════════════
clear
echo ""
echo "${B}  ToggleMaster — apresentacao pelo AWS CloudShell${R}"
echo ""

if ! command -v kubectl >/dev/null 2>&1; then
  echo "  ${D}instalando o kubectl (nao vem no CloudShell)...${R}"
  mkdir -p "$HOME/bin"
  curl -sL "https://dl.k8s.io/release/v1.36.2/bin/linux/amd64/kubectl" -o "$HOME/bin/kubectl"
  chmod +x "$HOME/bin/kubectl"
fi
export PATH="$HOME/bin:$PATH"
echo "  kubectl: $(kubectl version --client -o json 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin)["clientVersion"]["gitVersion"])' 2>/dev/null || echo instalado)"

echo "  ${D}configurando o acesso ao cluster...${R}"
aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" >/dev/null 2>&1 \
  || { echo "  ERRO: nao consegui acessar o cluster $CLUSTER. O lab esta ativo?"; exit 1; }

NLB=$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
      -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
KEY=$(kubectl get secret evaluation-secrets -n evaluation \
      -o jsonpath='{.data.SERVICE_API_KEY}' 2>/dev/null | base64 -d)
QURL=$(aws sqs get-queue-url --queue-name togglemaster-events --region "$REGION" \
      --query QueueUrl --output text 2>/dev/null)

[ -n "$NLB" ] || { echo "  ERRO: nao achei o NLB do ingress-nginx."; exit 1; }
[ -n "$KEY" ] || { echo "  ERRO: nao achei a SERVICE_API_KEY no Secret."; exit 1; }

echo ""
echo "  ${GR}tudo pronto${R}"
echo "  NLB:   ${D}$NLB${R}"
echo "  chave: ${D}${KEY:0:16}...${R}"
echo "  fila:  ${D}$QURL${R}"
echo ""
echo "  ${YL}${B}Se voce ainda NAO gravou o bloco B (9 conteineres locais),${R}"
echo "  ${YL}faca isso primeiro no Git Bash da sua maquina:${R}"
echo "  ${GR}  bash /c/Users/enzoo/Desktop/POSTECH/scripts/apresentar.sh${R}"
echo "  ${D}  (rode so ate o fim do bloco B e volte para ca)${R}"
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
pausa

# ════════════════════════════════════════════════════════════════════
bloco C "4:30 – 7:30" "Console AWS — a infraestrutura provisionada"
echo "  ${D}Este bloco e todo visual. Maximize o console e deixe o CloudShell${R}"
echo "  ${D}minimizado no rodape — voce volta pra ca no bloco D.${R}"

fala "Todo o provisionamento usou a LabRole — tanto a cluster role quanto a node role.
No AWS Academy nao e possivel criar IAM roles, entao essa role existente e
passada explicitamente em cada recurso que precisa de permissao."

console "EKS — o cluster e o node group" \
"Busque ${B}EKS${R} na barra de pesquisa → ${B}Clusters${R} → clique em ${B}togglemaster${R}|Aba ${B}Visao geral${R}: aponte ${B}Status Ativo${R} e ${B}versao 1.36${R}|Aba ${B}Computacao${R} → clique no grupo de nos ${B}ng-togglemaster${R}|Role ate ${B}Configuracao de escalabilidade do grupo de nos${R}|Aponte: ${B}minimo 1 · desejado 2 · maximo 4${R} — e o tipo ${B}t3.medium${R}|Aponte tambem ${B}Funcao do IAM do no${R} = ${B}LabRole${R} (e o ponto da fala)"

console "EKS — os workloads, direto na interface" \
"Ainda no cluster, va na aba ${B}Recursos${R}|No menu da esquerda: ${B}Workloads${R} → ${B}Deployments${R}|Mostre os 5 deployments, cada um no seu ${B}namespace${R}|Clique em ${B}evaluation-service${R} e mostre as replicas|${D}Guarde esta tela: no bloco F voce volta aqui e da F5 pra ver as replicas subindo${R}"

console "ECR — as 5 imagens publicadas" \
"Busque ${B}ECR${R} → ${B}Repositorios privados${R}|Mostre os ${B}5 repositorios${R}: auth, flag, targeting, evaluation, analytics|Clique em ${B}evaluation-service${R}|Aponte a tag ${B}v1${R}, o tamanho da imagem e a data do push"

console "RDS — as 3 instancias independentes" \
"Busque ${B}RDS${R} → ${B}Bancos de dados${R}|Mostre as ${B}3 instancias${R} com status ${B}Disponivel${R}: auth-db, flags-db, targeting-db|Clique em ${B}auth-db${R} → aba ${B}Conectividade e seguranca${R}|Aponte o ${B}endpoint${R} e a classe ${B}db.t3.micro${R}"

console "ElastiCache — o cache do hot path" \
"Busque ${B}ElastiCache${R} → no menu esquerdo ${B}Caches do Redis OSS${R}|Clique em ${B}togglemaster-redis${R}|Aponte o ${B}endpoint primario${R} e o no ${B}cache.t3.micro${R}"

console "EC2 — o Load Balancer que o Ingress criou sozinho" \
"Busque ${B}EC2${R} → menu esquerdo ${B}Balanceadores de carga${R}|Ache o LB com nome comecando em ${B}k8s-${R}, tipo ${B}network${R}|Aponte o ${B}nome DNS${R} — e a URL que voce vai chamar no bloco E|${YL}Fale: este NLB nao foi criado a mao. O Nginx Ingress Controller o provisionou${R}|${YL}sozinho, usando as permissoes que o no herda da LabRole.${R}"

console "SQS — a fila" \
"Busque ${B}SQS${R} → ${B}Filas${R} → clique em ${B}togglemaster-events${R}|Aba ${B}Detalhes${R}: aponte o tipo ${B}Standard${R}|Aba ${B}Monitoramento${R}: deixe esta aba aberta — no bloco G ela vai encher de graficos"

console "DynamoDB — a tabela de eventos" \
"Busque ${B}DynamoDB${R} → ${B}Tabelas${R} → clique em ${B}ToggleMasterAnalytics${R}|Aponte a ${B}chave de particao event_id${R} e o modo ${B}sob demanda${R}|Menu esquerdo: ${B}Explorar itens${R} → botao ${B}Executar${R}|Mostre alguns itens com user_id, flag_name, result e timestamp|${D}Guarde esta tela tambem — voce volta nela no bloco G${R}"

echo "  ${D}Agora reabra o CloudShell no rodape do console.${R}"
pausa

# ════════════════════════════════════════════════════════════════════
bloco D "7:30 – 9:00" "Os 5 microsservicos como Pods"
fala "Agora pelo terminal. Este e o AWS CloudShell, rodando dentro do proprio
console — ja autenticado com as credenciais da conta, sem configurar nada."
pausa
roda kubectl get nodes

fala "Cada aplicacao tem o proprio namespace, como o enunciado pede: auth, flags,
targeting, evaluation e analytics."
pausa
roda_sh "kubectl get pods -A -o wide 2>&1 | grep -vE 'kube-system|ingress-nginx'"

fala "Todos os Deployments tem requests e limits de CPU e memoria — o request de CPU
e a base de calculo do HPA — e readiness e liveness probe apontando para /health.
Os Services sao ClusterIP; quem expoe para fora e o Ingress."
pausa
roda_sh "kubectl get deploy,svc -A 2>&1 | grep -vE 'kube-system|ingress-nginx'"

fala "E aqui, do lado do Kubernetes, o mesmo Load Balancer que voce viu no console EC2."
pausa
roda kubectl get svc -n ingress-nginx ingress-nginx-controller

echo "  ${D}Quer mostrar um manifesto? Este e o HPA, com a justificativa nos comentarios:${R}"
pausa
roda_sh "kubectl get hpa evaluation-hpa -n evaluation -o yaml | head -30"

# ════════════════════════════════════════════════════════════════════
bloco E "9:00 – 10:30" "Ingress funcionando — curl no Load Balancer"
fala "Essas chamadas vao para o DNS do Network Load Balancer. O roteamento por path e
do Ingress: /flags vai para o flag-service, /rules para o targeting-service,
/evaluate para o evaluation-service."
pausa
echo "${GR}  \$ curl http://\$NLB/auth/health${R}"
printf "  -> "; curl -s -m 15 "http://$NLB/auth/health"; echo; echo

echo "${GR}  \$ curl http://\$NLB/flags -H \"Authorization: Bearer \$KEY\"${R}"
printf "  -> "; curl -s -m 15 "http://$NLB/flags" -H "Authorization: Bearer $KEY" | head -c 220; echo; echo

fala "E a avaliacao pela URL publica, com o rollout de 50 por cento: usuarios
diferentes recebem respostas diferentes."
pausa
echo "${GR}  \$ curl \"http://\$NLB/evaluate?user_id=<N>&flag_name=enable-new-dashboard\"${R}"; echo ""
for u in user-123 user-456 user-789 user-abc user-def user-ghi; do
  printf "  %-10s -> " "$u"
  curl -s -m 15 "http://$NLB/evaluate?user_id=$u&flag_name=enable-new-dashboard"; echo
done
echo ""

# ════════════════════════════════════════════════════════════════════
bloco F "10:30 – 14:00" "Carga no evaluation-service e o HPA escalando"
echo "  ${D}Estado inicial (tem que estar em 1 replica):${R}"; echo ""
kubectl get hpa -A
fala "Vou gerar carga contra o /evaluate. O HPA esta configurado para 70 por cento de
utilizacao media de CPU, minimo 1 e maximo 5 replicas. Repare na coluna TARGETS:
quando a CPU passa de 70 por cento, o controlador comeca a adicionar pods.
O HPA leva de 30 a 90 segundos para reagir — o metrics-server coleta a cada 15."
pausa

echo "${GR}  \$ kubectl apply -f - <<< (gerador de carga, 6 pods dentro do cluster)${R}"
kubectl apply -f - <<'LOADGEN'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: loadgen
  namespace: evaluation
spec:
  replicas: 6
  selector:
    matchLabels:
      app: loadgen
  template:
    metadata:
      labels:
        app: loadgen
    spec:
      containers:
        - name: loadgen
          image: curlimages/curl:8.10.1
          command: ["/bin/sh", "-c"]
          args:
            - |
              while true; do
                curl -s -o /dev/null --max-time 5 \
                  "http://evaluation-service.evaluation.svc.cluster.local:8004/evaluate?user_id=load-$$RANDOM&flag_name=enable-new-dashboard"
              done
          resources:
            requests:
              cpu: 50m
              memory: 32Mi
            limits:
              cpu: 200m
              memory: 64Mi
LOADGEN
echo ""
echo "  ${D}acompanhando o HPA — 12 amostras de 15 s (3 minutos)${R}"; echo ""
printf "  %-9s  %-30s  %-30s\n" "hora" "evaluation" "analytics"
printf "  %-9s  %-30s  %-30s\n" "─────────" "──────────────────────────────" "──────────────────────────────"
for i in $(seq 1 12); do
  EV=$(kubectl get hpa evaluation-hpa -n evaluation --no-headers 2>/dev/null | awk '{print $3" "$4"  ->  "$7" replicas"}')
  AN=$(kubectl get hpa analytics-hpa  -n analytics  --no-headers 2>/dev/null | awk '{print $3" "$4"  ->  "$7" replicas"}')
  printf "  %-9s  %-30s  %-30s\n" "$(date +%H:%M:%S)" "${EV:-...}" "${AN:-...}"
  sleep 15
done
echo ""
fala "Os dois HPAs subiram. O evaluation escalou porque recebeu a carga HTTP direta.
Mas repare no analytics: ninguem mandou carga nele. Ele escalou porque cada
avaliacao publica um evento no SQS, a fila encheu, o worker passou a trabalhar
mais, a CPU subiu — e o HPA reagiu. E o encadeamento inteiro funcionando."
pausa
roda_sh "kubectl get pods -n evaluation --no-headers 2>&1 | grep -v loadgen"
roda kubectl get pods -n analytics

console "As replicas subindo NA INTERFACE do EKS" \
"Volte na aba do ${B}EKS → Recursos → Workloads → Deployments${R}|Aperte ${B}F5${R}|Aponte a coluna de ${B}pods prontos${R}: evaluation e analytics nao estao mais em 1|Clique em ${B}analytics-service${R} → mostre a lista de pods, com os horarios de criacao diferentes|${YL}Fale: estes pods nasceram agora, criados pelo autoscaler, nao por mim.${R}"

echo "  ${D}derrubando o gerador de carga...${R}"
kubectl delete deployment loadgen -n evaluation >/dev/null 2>&1
echo "  ok"

# ════════════════════════════════════════════════════════════════════
bloco G "14:00 – 17:00" "SQS manual, analytics escalando e DynamoDB"
fala "Alem da carga HTTP, o enunciado pede o envio manual de mensagens para o SQS.
Vou publicar mensagens em lotes de 10, direto pela API da fila, sem passar pelo
evaluation-service."
pausa

TOTAL="${TOTAL_SQS:-2000}"
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "${GR}  \$ aws sqs send-message-batch --queue-url \$QURL --entries ... ${D}(x$((TOTAL/10)) lotes)${R}"
echo ""
enviadas=0
for ((b=0; b<TOTAL/10; b++)); do
  entries="["
  for ((i=0; i<10; i++)); do
    n=$(( b*10 + i ))
    [ $i -gt 0 ] && entries+=","
    res=$( [ $((n % 2)) -eq 0 ] && echo true || echo false )
    body="{\"user_id\":\"manual-user-$n\",\"flag_name\":\"enable-new-dashboard\",\"result\":$res,\"timestamp\":\"$TS\"}"
    esc=$(printf '%s' "$body" | python3 -c "import sys,json;print(json.dumps(sys.stdin.read()))")
    entries+="{\"Id\":\"m$n\",\"MessageBody\":$esc}"
  done
  entries+="]"
  ok=$(aws sqs send-message-batch --queue-url "$QURL" --region "$REGION" \
        --entries "$entries" --query "length(Successful)" --output text 2>/dev/null)
  enviadas=$(( enviadas + ${ok:-0} ))
  printf "\r  enviadas: %d/%d" "$enviadas" "$TOTAL"
done
echo ""; echo ""
echo "  ${D}profundidade da fila:${R}"
aws sqs get-queue-attributes --queue-url "$QURL" --region "$REGION" \
  --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible \
  --query "Attributes" --output table

console "A fila enchendo, no grafico do console" \
"Volte na aba do ${B}SQS → togglemaster-events → aba Monitoramento${R}|Aperte ${B}F5${R} (os graficos tem alguns segundos de atraso)|Aponte o pico em ${B}Numero de mensagens enviadas${R}|Aponte tambem ${B}Numero de mensagens recebidas${R} — e o analytics consumindo|${YL}Fale: o que sobe em enviadas fui eu; o que sobe em recebidas e o consumidor.${R}"

fala "O analytics-service consome essa fila. Quanto mais mensagens chegam, mais o
worker trabalha, mais CPU consome — e o HPA adiciona replicas."
pausa
roda kubectl get hpa -n analytics
roda kubectl get pods -n analytics

fala "E aqui o caminho completo fechado: evento publicado no SQS, consumido pelo
analytics-service, gravado no DynamoDB."
pausa
roda_sh "kubectl logs -n analytics deploy/analytics-service --tail 40 2>&1 | grep -i salvo | tail -5"
echo "  ${D}total de eventos na tabela:${R}"
roda_sh "aws dynamodb scan --table-name ToggleMasterAnalytics --region $REGION --select COUNT --output text | awk '{s+=\$1} END {print \"  \"s\" eventos\"}'"

console "Os dados manuais aparecendo na tabela" \
"Volte na aba do ${B}DynamoDB → ToggleMasterAnalytics → Explorar itens${R}|Aperte ${B}Executar${R} de novo|Em ${B}Filtros${R}: atributo ${B}user_id${R}, tipo ${B}String${R}, condicao ${B}Comeca com${R}, valor ${B}manual-user${R}|Aperte ${B}Executar${R}|${YL}Fale: estes sao os que eu publiquei na mao na fila, ha um minuto.${R}|Opcional: aba ${B}Monitorar${R} → grafico de ${B}Solicitacoes de gravacao${R} com o pico"

# ════════════════════════════════════════════════════════════════════
bloco H "17:00 – 19:00" "Desafios e justificativa da escalabilidade"
echo "  ${D}Sem terminal. Fale olhando para a camera — 4 pontos.${R}"
fala "1 — O codigo-fonte nao compilava.
Foram 6 defeitos corrigidos. O mais sutil estava no auth-service: o driver
pgx/stdlib era importado normalmente, mas ele existe so pelo efeito colateral do
init, que registra o driver no database/sql. Em Go, import nao usado e erro de
compilacao — e se alguem corrigisse apagando o import, viraria um erro de runtime
bem pior de diagnosticar: unknown driver pgx. O certo e o import em branco."
pausa
fala "2 — Limitacoes da LabRole.
O AWS Academy nao permite criar IAM roles. Isso elimina de saida o eksctl create
cluster, o KEDA, o Karpenter e o IRSA. Tudo foi provisionado passando a LabRole
existente explicitamente, no cluster e no node group."
pausa
fala "3 — O IMDS hop limit, o desafio mais interessante.
O plano era os pods herdarem a LabRole do no via IMDS, sem credencial nenhuma
dentro do cluster. Na pratica, analytics e evaluation retornavam Unable to locate
credentials. O managed node group sobe as instancias com hop limit 1 no metadata
service; um pod esta a 2 hops do 169.254.169.254, entao o pacote e descartado —
protecao deliberada do EKS para impedir que pods assumam a role do no. Duas
saidas: subir o hop limit para 2, enfraquecendo esse isolamento, ou injetar as
credenciais temporarias do lab como Secret. Escolhemos a segunda. O custo e
honesto: elas expiram em cerca de 4 horas. Em producao o certo seria IRSA ou
EKS Pod Identity."
pausa
fala "4 — Por que HPA por CPU e nao KEDA.
KEDA seria tecnicamente superior: escalaria pelo queueDepth do SQS, que e o sinal
direto do trabalho pendente, e escalaria de zero a N. Mas depende de IRSA, que
depende de criar IAM role — bloqueado no Academy. O workaround e indireto e
funciona: a fila enche, o worker processa mais, a CPU sobe, o HPA adiciona
replicas. O teste comprovou o encadeamento. As limitacoes a gente reconhece:
CPU e um proxy indireto; se o consumo fosse limitado por I/O o sinal seria fraco.
E nao ha escala a zero."
pausa

# ════════════════════════════════════════════════════════════════════
bloco I "19:00 – 20:00" "Fechamento"
fala "Recapitulando: 5 microsservicos conteinerizados com build multi-stage,
infraestrutura provisionada na AWS com EKS, ECR, 3 RDS, ElastiCache, DynamoDB e
SQS, implantados com namespaces separados, probes, secrets em base64, requests e
limits, expostos por Nginx Ingress, e escalando automaticamente por HPA de CPU
nos dois servicos exigidos. Os recursos serao destruidos logo apos esta gravacao
para nao consumir o orcamento do laboratorio. Obrigado."

echo ""; echo ""
echo "${CY}${B}════════════════════════════════════════════════════════════════════${R}"
echo "${B}  FIM${R}"
echo ""
echo "  ${YL}Depois de parar a gravacao, na sua maquina:${R}"
echo "  ${GR}\$ bash /c/Users/enzoo/Desktop/POSTECH/scripts/teardown.sh${R}"
echo "${CY}${B}════════════════════════════════════════════════════════════════════${R}"
echo ""
