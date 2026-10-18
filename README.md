# ToggleMaster — Tech Challenge Fase 2 (POSTECH/FIAP)

Ecossistema de 5 microsserviços de *feature flags*, conteinerizado com Docker e implantado
em **Kubernetes na AWS (EKS)** com escalabilidade automática por HPA.

> **Caminho seguido: Opção A — AWS Academy Learner Lab.** Sem criação de IAM roles;
> todos os recursos usam a `LabRole` existente. Região `us-east-1`.

---

## Arquitetura

| Serviço | Stack | Porta | Data store | Papel |
|---|---|---|---|---|
| `auth-service` | Go 1.22 | 8001 | PostgreSQL (RDS) | Emite e valida chaves de API |
| `flag-service` | Python/Flask | 8002 | PostgreSQL (RDS) | CRUD das definições de flags |
| `targeting-service` | Python/Flask | 8003 | PostgreSQL (RDS) | Regras de segmentação (JSONB) |
| `evaluation-service` | Go 1.22 | 8004 | Redis (ElastiCache) | *Hot path*: decide `true`/`false` |
| `analytics-service` | Python/Flask + worker | 8005 | DynamoDB | Consome SQS e grava eventos |

### Fluxo de uma avaliação

```
cliente → GET /evaluate?user_id=X&flag_name=Y
            ↓
     evaluation-service
            ↓
      cache Redis? ──sim──→ decisão (Cache HIT)
            │ não
            ↓
   flag-service + targeting-service  (em paralelo, goroutines)
            ↓
   regra PERCENTAGE: bucket = SHA1(user_id + flag_name) % 100
            ↓
     decisão true/false ──→ resposta ao cliente
            ↓
     evento publicado no SQS
            ↓
     analytics-service (long polling, 20s)
            ↓
     DynamoDB ToggleMasterAnalytics
```

O *bucketing* é **determinístico**: o mesmo usuário sempre cai do mesmo lado da regra
de 50%, o que é o comportamento correto para uma feature flag.

### Por que três data stores diferentes

| Store | Porque este e não outro |
|---|---|
| **RDS PostgreSQL** | Dados de configuração: baixo volume, alta consistência, relacionamentos e constraints (`UNIQUE` no nome da flag). Escrita rara, leitura por chave de negócio. |
| **ElastiCache Redis** | O `/evaluate` é o *hot path* — precisa responder em milissegundos e é chamado a cada request da aplicação cliente. Cache com TTL de 30s absorve a carga e protege os bancos. |
| **DynamoDB** | Ingestão de eventos de análise: volume alto, escrita append-only, sem joins, chave de partição simples (`event_id`). NoSQL serverless escala sem gerenciar capacidade. |

---

## Ambiente local (9 contêineres)

```bash
docker compose up -d --build
docker compose ps
```

| # | Contêiner | Papel |
|---|---|---|
| 1-2 | `tm-postgres-auth`, `tm-postgres-flags` | 2 instâncias PostgreSQL (a segunda hospeda `flags_db` **e** `targeting_db`) |
| 3 | `tm-redis` | Cache do evaluation |
| 4 | `tm-dynamodb-local` | DynamoDB Local (porta 8000) |
| 5-9 | os 5 microsserviços | |

**SQS não tem equivalente local** — o ambiente local usa a **fila real da AWS**. As credenciais
temporárias do Learner Lab **não ficam em nenhum arquivo do projeto**: `~/.aws` é montado
somente-leitura nos dois contêineres que falam com a AWS.

Criar a tabela no DynamoDB Local (uma vez, após subir):

```bash
aws dynamodb create-table --table-name ToggleMasterAnalytics --attribute-definitions AttributeName=event_id,AttributeType=S --key-schema AttributeName=event_id,KeyType=HASH --billing-mode PAY_PER_REQUEST --endpoint-url http://localhost:8000
```

### Teste ponta a ponta local

```bash
KEY=$(curl -s -X POST http://localhost:8001/admin/keys -H "Authorization: Bearer $MASTER_KEY" -H "Content-Type: application/json" -d '{"name":"servico-interno"}' | jq -r .key)
curl -s -X POST http://localhost:8002/flags -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d '{"name":"enable-new-dashboard","is_enabled":true}'
curl -s -X POST http://localhost:8003/rules -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d '{"flag_name":"enable-new-dashboard","is_enabled":true,"rules":{"type":"PERCENTAGE","value":50}}'
curl -s "http://localhost:8004/evaluate?user_id=user-123&flag_name=enable-new-dashboard"
```

---

## Nuvem (AWS)

### Provisionamento

Tudo criado via **AWS CLI** passando a `LabRole` existente — nenhuma IAM role foi criada.
`eksctl create cluster` **não** foi usado (ele cria roles próprias, o que o Learner Lab bloqueia).

| Recurso | Nome |
|---|---|
| EKS | `togglemaster` (k8s 1.36), cluster role `LabRole` |
| Node group | `ng-togglemaster`, t3.medium, **min 1 / desejado 2 / máx 4**, node role `LabRole` |
| ECR | 5 repositórios, um por serviço, tag `v1` |
| RDS | `auth-db`, `flags-db`, `targeting-db` (3 instâncias independentes, db.t3.micro) |
| ElastiCache | `togglemaster-redis` (cache.t3.micro) |
| DynamoDB | `ToggleMasterAnalytics`, PK `event_id` (S), on-demand |
| SQS | `togglemaster-events` (Standard) |

### Deploy

```bash
aws eks update-kubeconfig --name togglemaster --region us-east-1

kubectl apply -f k8s/00-namespaces.yaml
bash scripts/gen-secrets.sh "<SERVICE_API_KEY>"     # gera k8s/secrets.yaml em base64
bash scripts/gen-aws-creds-secret.sh                # fallback de credenciais do Academy
kubectl apply -f k8s/
```

**Ordem importa**: `auth-service` primeiro, porque a `SERVICE_API_KEY` usada pelos outros
serviços é criada chamando o `/admin/keys` dele.

### Estrutura dos manifestos

```
k8s/
├── 00-namespaces.yaml   5 namespaces: auth, flags, targeting, evaluation, analytics
├── 01-auth.yaml         ConfigMap + Deployment + Service (ClusterIP)
├── 02-flags.yaml
├── 03-targeting.yaml
├── 04-evaluation.yaml
├── 05-analytics.yaml
├── 06-ingress.yaml      1 Ingress por namespace, ingressClassName: nginx
├── 07-hpa.yaml          HPA de evaluation e analytics (CPU 70%)
├── 08-loadgen.yaml      gerador de carga para demonstrar o HPA
└── secrets.yaml         GERADO por scripts/gen-secrets.sh (não versionado)
```

Boas práticas aplicadas em todos os Deployments: `resources.requests/limits`,
`readinessProbe` + `livenessProbe` em `/health`, imagens do ECR com tag explícita,
usuário não-root nos contêineres e um namespace por serviço.

### Rotas via Ingress (NLB)

| Caminho | Serviço |
|---|---|
| `/auth/...` | auth-service:8001 (com `rewrite-target`) |
| `/flags` | flag-service:8002 |
| `/rules` | targeting-service:8003 |
| `/evaluate` | evaluation-service:8004 |
| `/analytics/...` | analytics-service:8005 |

---

## Escalabilidade

Dois HPAs por CPU (`averageUtilization: 70`, min 1 / máx 5).

**Por que HPA por CPU e não KEDA:** KEDA escalaria o `analytics-service` diretamente pelo
`queueDepth` do SQS — inclusive de zero para N — mas exige **IRSA**, que depende de criar
uma IAM role. Isso é bloqueado no AWS Academy. O workaround: a fila enche → o worker
processa mais mensagens → a CPU sobe → o HPA adiciona réplicas.

**Trade-off honesto:** CPU é um proxy *indireto* da profundidade da fila. Se o consumo
fosse limitado por I/O em vez de CPU, o sinal seria fraco. E o HPA por CPU não escala a zero.

### Resultado medido

| Serviço | Réplicas | Pico de CPU |
|---|---|---|
| `evaluation-service` | 1 → **4** | 266% / 70% |
| `analytics-service` | 1 → **5** | 292% / 70% |

**40.620 eventos** processados ponta a ponta (`/evaluate` → SQS → analytics → DynamoDB),
com a fila drenada ao final (`ApproximateNumberOfMessages: 0`).

Gerar carga (equivalente ao `k8s/08-loadgen.yaml`):

```bash
hey -z 120s -c 50 "http://<NLB>/evaluate?user_id=u1&flag_name=enable-new-dashboard"
```

---

## Limpeza (a ordem importa)

```bash
bash scripts/teardown.sh
```

O Service `LoadBalancer` do ingress-nginx precisa ser removido **antes** do cluster,
senão o NLB fica órfão consumindo o orçamento do lab.

---

## Documentos

- [`RELATORIO.md`](RELATORIO.md) — relatório de entrega
- [`INFRA.md`](INFRA.md) — endpoints provisionados (não versionado)
- [`evidencias/`](evidencias/) — saídas de comando coletadas durante a execução
