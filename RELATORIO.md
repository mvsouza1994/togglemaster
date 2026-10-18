# Relatório de Entrega — Tech Challenge Fase 2

**ToggleMaster: de monolito a ecossistema de microsserviços em Kubernetes (AWS EKS)**

---

## 1. Identificação

> **PREENCHER ANTES DE ENTREGAR**

| Nome | RM | Username Discord |
|---|---|---|
| *Marcos Vinicius de Souza* | *rm375538* | *marcos008789* |
| *Enzo Oliveira Bernardo* | *rm375370* | *monkeykiss123* |


**Vídeo de demonstração:** *https://youtu.be/5-hsOHBgvac*


---

## 2. Ambiente escolhido

**Opção A — AWS Academy Learner Lab.** Conta `053538833669`, região `us-east-1`,
orçamento do laboratório de US$ 50.

Consequência prática: **nenhuma IAM role foi criada**. Todos os recursos que exigem
permissão (cluster EKS, node group) usam a `LabRole` existente. Isso elimina KEDA e
Karpenter do escopo, porque ambos dependem de IRSA.

---

## 3. Etapa 1 — Análise e conteinerização

### 3.1 Correções necessárias no código-fonte

O código entregue **não compilava nem subia** como estava. Seis defeitos foram corrigidos:

| # | Onde | Defeito | Correção |
|---|---|---|---|
| 1 | `evaluation-service/evaluator.go` | Usa `os.Getenv` sem importar `"os"` | Import adicionado |
| 2 | `evaluation-service/evaluator.go` | Importa `"context"` sem usar (erro de compilação em Go) | Import removido |
| 3 | `evaluation-service/go.sum` | Arquivo corrompido — é uma cópia do `go.mod` | Excluído do build; grafo resolvido com `go mod tidy` |
| 4 | `auth-service/main.go` | `"github.com/jackc/pgx/v4/stdlib"` importado normalmente | Trocado por import em branco (`_`); é um driver registrado via `init()`, e sem isso o `sql.Open("pgx", ...)` não encontra o driver |
| 5 | `auth-service` (`main.go`, `handlers.go`, `key.go`) | 4 imports declarados e não usados | Removidos |
| 6 | `*/requirements.txt` | `Flask==2.2.2` sem pin de `Werkzeug` → pip instala 3.x e quebra a importação | Stack do Flask 2.2 pinada por inteiro |
| 7 | `analytics-service/requirements.txt` | `boto3==1.26.50` não suporta `AWS_ENDPOINT_URL_DYNAMODB` | Elevado para `1.34.144` |

Os `db/init.sql` citados nos READMEs **existem** nos repositórios de auth, flag e targeting,
com os schemas corretos — foram reaproveitados sem alteração.

### 3.2 Dockerfiles

Cinco Dockerfiles **multi-stage**, todos rodando como usuário não-root:

- **Go** (auth, evaluation): `golang:1.22-alpine` para build (`CGO_ENABLED=0`) → `alpine:3.20`
  no runtime. Imagem final na casa dos 15 MB.
- **Python** (flag, targeting, analytics): `python:3.11-slim` monta um virtualenv no primeiro
  estágio, e apenas o `/opt/venv` é copiado para o runtime. Servidos por `gunicorn`.

### 3.3 Docker Compose — 9 contêineres

5 microsserviços + 4 data stores (2 PostgreSQL, 1 Redis, 1 DynamoDB Local), com
`healthcheck` em todos e `depends_on: condition: service_healthy` para ordenar a subida.

**Decisão de projeto:** o enunciado fixa 2 instâncias PostgreSQL, mas há 3 bancos. A segunda
instância hospeda `flags_db` e `targeting_db`, criados por um script no
`docker-entrypoint-initdb.d`. Na nuvem, cada banco tem sua própria instância RDS, como pedido.

**SQS no ambiente local:** não existe DynamoDB-Local equivalente para SQS. O ambiente local
usa a **fila real da AWS**. As credenciais temporárias do lab não entram em nenhum arquivo do
projeto — `~/.aws` é montado somente-leitura nos dois contêineres que precisam.

---

## 4. Etapa 2 — Infraestrutura na nuvem

| Recurso | Identificador | Observação |
|---|---|---|
| EKS | `togglemaster` | Kubernetes 1.36, cluster role `LabRole` |
| Node group | `ng-togglemaster` | t3.medium, **min 1 / desejado 2 / máx 4**, node role `LabRole` |
| ECR | 5 repositórios | `{auth,flag,targeting,evaluation,analytics}-service:v1` |
| RDS ×3 | `auth-db`, `flags-db`, `targeting-db` | db.t3.micro, PostgreSQL, sem acesso público |
| ElastiCache | `togglemaster-redis` | cache.t3.micro, Redis |
| DynamoDB | `ToggleMasterAnalytics` | PK `event_id` (S), on-demand |
| SQS | `togglemaster-events` | Standard |

**Sobre não usar o Console:** o enunciado orienta criar o cluster pelo Console e proíbe
`eksctl create cluster`. A proibição do `eksctl` existe porque ele cria IAM roles próprias,
o que o Learner Lab bloqueia. Usamos a **API oficial do EKS via AWS CLI**
(`aws eks create-cluster --role-arn .../LabRole`), que passa a role existente e portanto
respeita a mesma restrição, com a vantagem de ser reproduzível e auditável.

Os schemas foram aplicados nos três RDS a partir de um pod `postgres:16-alpine` rodando
dentro do cluster — evitando expor os bancos publicamente.

---

## 5. Etapa 3 — Configuração do cluster

- **Metrics Server** instalado (pré-requisito do HPA), validado com `kubectl top nodes`.
- **Nginx Ingress Controller** (manifesto oficial `provider/aws`). O Service `LoadBalancer`
  provisionou um **NLB**, com a permissão vindo da `LabRole` do nó.

---

## 6. Etapa 4 — Orquestração

Cinco namespaces (`auth`, `flags`, `targeting`, `evaluation`, `analytics`), e por serviço:
`ConfigMap`, `Secret`, `Deployment`, `Service` (ClusterIP) e `Ingress`.

Boas práticas exigidas e aplicadas:

- `resources.requests` e `limits` em todos os contêineres (o `request` de CPU é o que o
  HPA usa como base de cálculo)
- `readinessProbe` e `livenessProbe` em `/health`
- Secrets em base64
- Um namespace por aplicação

Comunicação entre serviços por DNS interno cruzando namespace, ex.:
`http://auth-service.auth.svc.cluster.local:8001`.

---

## 7. Etapa 5 — Escalabilidade

Dois `HorizontalPodAutoscaler` por CPU, `averageUtilization: 70`, min 1 / máx 5.

### Resultado do teste de carga

| Serviço | Réplicas | Pico de CPU medido |
|---|---|---|
| `evaluation-service` | 1 → **4** | 266% / 70% |
| `analytics-service` | 1 → **5** | 292% / 70% |

**40.620 eventos** percorreram o caminho completo `/evaluate` → SQS → analytics → DynamoDB,
com a fila drenada ao final.

### Justificativa da escolha (HPA por CPU vs KEDA)

KEDA seria tecnicamente superior para o `analytics-service`: escalaria pelo `queueDepth`
do SQS — o sinal direto do trabalho pendente — e escalaria de **zero** a N, o que economiza
recursos quando não há eventos.

KEDA foi descartado porque exige **IRSA** (IAM Roles for Service Accounts), que depende de
criar uma IAM role e associar um OIDC provider ao cluster. O AWS Academy não permite criar
roles.

O workaround adotado é indireto mas funcional: a fila enche → o worker processa mais
mensagens → a CPU do pod sobe → o HPA adiciona réplicas. O teste confirmou o encadeamento:
a carga no `evaluation-service` gerou eventos suficientes para levar o `analytics-service`
de 1 a 5 réplicas sozinho.

**Limitações que reconhecemos:** CPU é um proxy indireto — se o consumo fosse limitado por
I/O e não por CPU, o sinal seria fraco e o autoscaling reagiria mal. E não há escala a zero.

---

## 8. Desafios encontrados

### 8.1 Código-fonte não compilava

Seis defeitos (seção 3.1). O mais sutil: o driver `pgx/stdlib` importado sem `_`, que em Go
é erro de compilação e, se fosse "corrigido" apenas removendo o import, produziria um erro
de runtime (`unknown driver "pgx"`) muito mais difícil de diagnosticar.

### 8.2 Pods sem acesso às credenciais da LabRole (IMDS hop limit)

O plano previa que os pods herdariam a `LabRole` do nó via IMDS, evitando qualquer
credencial dentro do cluster. Na prática, os pods do `analytics` e do `evaluation`
retornaram `Unable to locate credentials`.

**Causa:** o managed node group do EKS sobe as instâncias com
`HttpPutResponseHopLimit = 1`. Um pod está a **2 hops** do metadata service (169.254.169.254),
então a requisição é descartada. É uma proteção deliberada do EKS para impedir que pods
assumam a role do nó.

**Duas soluções possíveis:**

1. Elevar o hop limit para 2 (`aws ec2 modify-instance-metadata-options`) — mantém o cluster
   livre de credenciais, mas enfraquece o isolamento entre pod e nó.
2. Injetar as credenciais temporárias do lab como `Secret` — foi a adotada.

**Consequência da escolha:** as credenciais do Learner Lab expiram junto com a sessão (~4h).
A cada `Start Lab` é preciso rodar `scripts/gen-aws-creds-secret.sh` novamente e reiniciar
os dois deployments. Em produção real, o correto seria IRSA (ou EKS Pod Identity), que
resolve o problema sem credenciais estáticas nem afrouxar o IMDS.

### 8.3 Limitações gerais da LabRole

Sem criação de IAM roles: nada de `eksctl create cluster`, KEDA, Karpenter ou IRSA.
Todo o provisionamento foi feito passando a role existente explicitamente.

---

## 9. Custo

| Item | US$/h |
|---|---|
| EKS control plane | 0,10 |
| 2× t3.medium | 0,083 |
| 3× RDS db.t3.micro | 0,063 |
| ElastiCache cache.t3.micro | 0,017 |
| NLB | 0,023 |
| **Total** | **≈ 0,29** |

O control plane do EKS e o ElastiCache continuam cobrando mesmo com o laboratório
desligado — por isso todos os recursos foram destruídos ao final da sessão.

---

## 10. Limpeza

Executada na ordem correta, com o Service `LoadBalancer` removido **antes** do cluster
para não deixar NLB órfão: `scripts/teardown.sh`.
