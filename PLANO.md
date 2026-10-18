# Tech Challenge Fase 2 — Plano de Execução (Opção A: AWS Academy)

> **ToggleMaster** — 5 microsserviços → Docker → ECR → EKS (LabRole) → HPA.
> Vale 90% da nota da fase. Entregáveis: vídeo (≤20 min) + relatório PDF/txt.
> Caminho escolhido: **Opção A — AWS Academy Learner Lab** (sem criar IAM roles; usar sempre a `LabRole`; região `us-east-1`).

---

## Arquitetura (mapeada a partir do código já clonado nesta pasta)

| Serviço | Stack | Porta | Depende de | Variáveis de ambiente |
|---|---|---|---|---|
| `auth-service` | Go 1.21 | 8001 | PostgreSQL (`auth_db`) | `DATABASE_URL`, `PORT`, `MASTER_KEY` |
| `flag-service` | Python/Flask + gunicorn | 8002 | PostgreSQL (`flags_db`), auth | `DATABASE_URL`, `PORT`, `AUTH_SERVICE_URL` |
| `targeting-service` | Python/Flask + gunicorn | 8003 | PostgreSQL (`targeting_db`), auth | `DATABASE_URL`, `PORT`, `AUTH_SERVICE_URL` |
| `evaluation-service` | Go 1.21 | 8004 | Redis, flag, targeting, SQS (produtor) | `PORT`, `REDIS_URL`, `FLAG_SERVICE_URL`, `TARGETING_SERVICE_URL`, `SERVICE_API_KEY`, `AWS_SQS_URL`, `AWS_REGION` |
| `analytics-service` | Python/Flask + worker SQS | 8005 | SQS (consumidor), DynamoDB | `PORT`, `AWS_SQS_URL`, `AWS_DYNAMODB_TABLE`, `AWS_REGION` |

**Fluxo:** cliente → `/evaluate` (evaluation) → cache Redis → (miss) flag+targeting → decisão true/false → evento na fila SQS → analytics consome → grava no DynamoDB `ToggleMasterAnalytics` (PK: `event_id` tipo String).

Todos os serviços expõem `GET /health` (usaremos nas probes do K8s).

---

## ⚠️ Armadilhas descobertas no código-fonte (resolver na Etapa 1)

1. **`evaluation-service/evaluator.go` não compila**: usa `os.Getenv(...)` (linhas 106 e 133) mas **não importa `"os"`**. Corrigir o bloco de imports (e conferir se `"context"` importado é realmente usado — import não usado também é erro em Go).
2. **`requirements.txt` (flag/targeting/analytics): Flask 2.2.2 sem pin de Werkzeug** → o pip instala Werkzeug 3.x, que quebra o Flask 2.2.2 na importação. Adicionar `Werkzeug==2.2.3` aos três.
3. **`analytics-service` usa `boto3==1.26.50`**, que **não** suporta a env var `AWS_ENDPOINT_URL_DYNAMODB`. Para apontar para o **DynamoDB Local** no docker-compose sem mudar código, subir para `boto3>=1.34`.
4. **Os `db/init.sql` citados nos READMEs não existem nos repositórios.** Vamos criá-los deduzindo o schema das queries:
   - `api_keys(id SERIAL PK, name TEXT, key_hash TEXT, is_active BOOLEAN DEFAULT true, created_at)`
   - `flags(id SERIAL PK, name TEXT UNIQUE, description TEXT, is_enabled BOOLEAN, created_at, updated_at)`
   - `targeting_rules(id SERIAL PK, flag_name TEXT UNIQUE, is_enabled BOOLEAN, rules JSONB, created_at, updated_at)`
5. **Não há SQS local**: o enunciado fixa 9 contêineres (5 apps + 2 Postgres + 1 Redis + 1 DynamoDB Local). O `evaluation-service` tolera `AWS_SQS_URL` vazia (só loga `[SQS_DISABLED]`), mas o `analytics-service` **exige** a fila. → Na demo local, usar a **fila SQS real** da AWS com o lab ativo (credenciais temporárias no `.env`).
6. **Credenciais do Academy expiram a cada sessão (~4h)**: refazer o copy/paste do "AWS Details → AWS CLI" a cada `Start Lab`. **Dentro do EKS isso não é problema**: os pods herdam a `LabRole` do nó via IMDS — por isso NÃO vamos colocar access keys nos Secrets do cluster.
7. **Ao final de tudo, deletar o Service/Ingress do LoadBalancer ANTES de deletar o cluster** — senão o NLB fica órfão consumindo o budget do lab.

---

## Etapa 0 — Preparação

**Máquina local (Windows):** Docker ✅ · docker compose ✅ · kubectl ✅ · Python ✅ · **AWS CLI v2 ❌ (instalar)** · helm (dispensável — usaremos `kubectl apply`).

```bash
winget install -e --id Amazon.AWSCLI
```

**AWS Academy (a cada sessão de trabalho):**
1. Entrar no curso no `awsacademy.instructure.com` → *Modules* → *Launch AWS Academy Learner Lab* → **Start Lab** (aguardar bolinha verde).
2. Clicar em **AWS Details** → **AWS CLI: Show** → copiar o bloco (`aws_access_key_id`, `aws_secret_access_key`, `aws_session_token`).
3. Colar em `C:\Users\enzoo\.aws\credentials` (perfil `[default]`) e garantir `region = us-east-1` em `C:\Users\enzoo\.aws\config`.
4. Testar: `aws sts get-caller-identity`.

**Budget:** o Learner Lab tem ~US$50. Custo com tudo de pé: EKS control plane US$0,10/h + 2×t3.medium ~US$0,17/h + 3×RDS t3.micro ~US$0,05/h + ElastiCache t3.micro ~US$0,02/h ≈ **US$0,35/h**. O control plane do EKS e o ElastiCache **continuam cobrando mesmo com o lab "off"** → concentrar as etapas de nuvem em poucas sessões, gravar o vídeo e **deletar tudo ao final**.

---

## Etapa 1 — Conteinerização e ambiente local (não precisa de AWS, exceto SQS na demo)

1. **Correções de código** (armadilhas 1–3 acima).
2. **Criar `db/init.sql`** em cada serviço de banco (auth, flag, targeting) — schemas da armadilha 4.
3. **5 Dockerfiles multi-stage:**
   - Go (auth, evaluation): `golang:1.22-alpine` (build, `CGO_ENABLED=0`) → `alpine` + `ca-certificates` (runtime). Imagem final ~15 MB.
   - Python (flag, targeting, analytics): `python:3.11-slim`, instalar requirements em camada separada, rodar com `gunicorn`.
4. **`docker-compose.yml` na raiz** com exatamente 9 contêineres:
   - `postgres-auth` (auth_db) e `postgres-flags` (flags_db + targeting_db via script de init) — "2 instâncias PostgreSQL" do enunciado; montar os `init.sql`.
   - `redis` (redis:7-alpine).
   - `dynamodb-local` (amazon/dynamodb-local, porta 8000).
   - 5 apps, com `depends_on` + healthchecks; analytics com `AWS_ENDPOINT_URL_DYNAMODB=http://dynamodb-local:8000` e SQS real; evaluation com SQS real (ou desabilitado quando sem lab).
   - `.env` na raiz (gitignored) com credenciais temporárias do Academy para SQS.
5. **Criar a tabela no DynamoDB Local** (one-shot): `aws dynamodb create-table ... --endpoint-url http://localhost:8000` (ou script Python).
6. **Roteiro de teste E2E local** (mesma sequência que vai pro vídeo):
   1. `docker compose up -d --build` → `docker compose ps` mostra 9 contêineres saudáveis.
   2. Criar chave de API: `POST :8001/admin/keys` com `Authorization: Bearer <MASTER_KEY>`.
   3. Criar flag: `POST :8002/flags` (`enable-new-dashboard`, `is_enabled: true`).
   4. Criar regra 50%: `POST :8003/rules`.
   5. Avaliar: `GET ":8004/evaluate?user_id=user-123&flag_name=enable-new-dashboard"` → true/false; repetir p/ ver `Cache HIT` no log.
   6. Ver analytics consumindo a fila e gravando no DynamoDB Local (`aws dynamodb scan --endpoint-url http://localhost:8000`).

---

## Etapa 2 — Infraestrutura AWS (Console, `us-east-1`, sempre `LabRole`)

> Anotar TODOS os endpoints num arquivo `INFRA.md` (gitignored) conforme for criando.

### 2.1 Cluster EKS (Console — NÃO usar `eksctl create cluster`)
- EKS → *Create cluster* → **Custom configuration** (desligar "quick config") → nome `togglemaster`, versão default.
- **Cluster IAM role: `LabRole`**.
- Auth mode: *EKS API and ConfigMap*. VPC default, todas as subnets (2+ AZs), endpoint **Public**.
- Add-ons default (vpc-cni, coredns, kube-proxy). Criar e aguardar ~10–15 min (status *Active*).

### 2.2 Managed Node Group (Console)
- Cluster → *Compute* → *Add node group*: nome `ng-togglemaster`, **Node IAM role: `LabRole`** (crucial — os pods herdarão as permissões de SQS/DynamoDB daqui).
- AMI Amazon Linux 2023, instância `t3.medium`, disco 20 GB.
- **Scaling: Min 1 / Desired 2 / Max 4** (exigido no enunciado). Aguardar nós *Ready*.

### 2.3 ECR — 5 repositórios + push
```
aws ecr create-repository --repository-name auth-service   (repetir p/ os 5)
aws ecr get-login-password | docker login --username AWS --password-stdin <ACCOUNT>.dkr.ecr.us-east-1.amazonaws.com
docker build -t <ACCOUNT>.dkr.ecr.us-east-1.amazonaws.com/auth-service:v1 ./auth-service   (build → tag → push dos 5)
```

### 2.4 RDS — 3 instâncias PostgreSQL independentes
- Para cada uma (`auth-db`, `flags-db`, `targeting-db`): *Standard create* → PostgreSQL 16 → template **Free tier/Dev-Test** → `db.t3.micro` → 20 GB, sem Multi-AZ, sem backup.
- VPC default; **Security Group**: liberar `5432` para o CIDR da VPC (`172.31.0.0/16`) — assim os pods do EKS alcançam.
- *Initial database name*: `auth_db` / `flags_db` / `targeting_db`. Usuário `postgres`, senha forte anotada.
- Rodar cada `init.sql` de dentro do cluster (pod utilitário `postgres:16` com `psql`) — evita expor o RDS publicamente.

### 2.5 ElastiCache Redis
- *Design your own cache* → Redis OSS, modo cluster **off**, 1 nó `cache.t3.micro`, VPC default, SG liberando `6379` para `172.31.0.0/16`, sem TLS/auth (lab). Anotar o *Primary endpoint*.

### 2.6 DynamoDB
- Tabela **`ToggleMasterAnalytics`**, partition key **`event_id` (String)**, capacity **On-demand**.

### 2.7 SQS
- Fila **Standard** `togglemaster-events` (defaults). Anotar a **URL** da fila.

---

## Etapa 3 — Configurar o cluster

```
aws eks update-kubeconfig --name togglemaster --region us-east-1
kubectl get nodes            # 2 nós Ready
```
- **Metrics Server** (necessário p/ HPA): `kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml` → validar com `kubectl top nodes`.
- **Nginx Ingress Controller** (manifest oficial `deploy/static/provider/aws/deploy.yaml` do ingress-nginx). O Service `LoadBalancer` cria um **NLB** (a permissão vem da LabRole). Aguardar `EXTERNAL-IP` em `kubectl get svc -n ingress-nginx`.

---

## Etapa 4 — Manifestos Kubernetes (pasta `k8s/` na raiz)

- **Namespaces** (um por serviço, como pede o enunciado): `auth`, `flags`, `targeting`, `evaluation`, `analytics`.
- Por serviço: `deployment.yaml`, `service.yaml` (ClusterIP), `secret.yaml`, `configmap.yaml`.
- **Secrets** (base64): `DATABASE_URL` (com endpoint RDS), `MASTER_KEY`, `SERVICE_API_KEY`, `REDIS_URL` (`redis://<endpoint-elasticache>:6379`), `AWS_SQS_URL`. **Sem access keys da AWS** — pods usam a LabRole do nó (workaround Academy). Fallback documentado: se o SDK não pegar credencial via IMDS, injetar as 3 credenciais temporárias num Secret (e renovar por sessão).
- **ConfigMaps**: URLs internas cross-namespace (`http://auth-service.auth.svc.cluster.local:8001`, etc.), `AWS_REGION=us-east-1`, `AWS_DYNAMODB_TABLE=ToggleMasterAnalytics`.
- **Boas práticas exigidas**: `resources.requests/limits` (ex.: 100m/128Mi → 250m/256Mi; HPA precisa do request de CPU), `readinessProbe` + `livenessProbe` em `/health`, imagens do ECR com tag explícita.
- **Ingress** (um recurso por namespace, `ingressClassName: nginx`):
  - `/auth` → auth-service:8001 (com rewrite: `/auth/validate` → `/validate`)
  - `/flags` → flag-service:8002 · `/rules` → targeting-service:8003 · `/evaluate` → evaluation-service:8004 (paths já batem com as apps)
- **Ordem de deploy**: auth → (criar `SERVICE_API_KEY` real via `/auth/admin/keys`) → flag/targeting → evaluation → analytics.
- Validar: `kubectl get pods -A`, e os curls do roteiro E2E apontando para `http://<DNS-do-NLB>/...`.

---

## Etapa 5 — Escalabilidade (HPA — caminho do Academy, sem KEDA)

- `hpa.yaml` do **evaluation-service**: `targetCPUUtilizationPercentage: 70`, min 1, max 5.
- `hpa.yaml` do **analytics-service**: CPU 70%, min 1, max 5.
- **Justificativa (vai pro vídeo/relatório)**: KEDA escalaria pelo `queueDepth` do SQS, mas exige IRSA (criação de IAM role), bloqueado no Academy. O workaround: fila enche → analytics processa mais → CPU sobe → HPA escala. Trade-off honesto: HPA por CPU é um *proxy* indireto da profundidade da fila e não escala a zero.
- **Teste de carga do evaluation** — instalar `hey` (`winget install -e --id rakyll.hey` ou baixar binário):
  `hey -z 60s -c 50 "http://<NLB>/evaluate?user_id=u1&flag_name=enable-new-dashboard"` → acompanhar `kubectl get hpa -w` e `kubectl get pods -n evaluation -w`.
- **Teste do analytics**: loop enviando centenas de `aws sqs send-message` → ver HPA subir réplicas → itens aparecendo no DynamoDB (console → *Explore table items*).

---

## Etapa 6 — Entregáveis

### Roteiro do vídeo (≤20 min)
1. (2 min) Arquitetura: diagrama dos 5 serviços + data stores; diferença de propósito **RDS** (relacional/consistência p/ CRUD) × **ElastiCache** (cache em memória p/ hot path, TTL 30s) × **DynamoDB** (NoSQL serverless p/ ingestão de eventos em escala).
2. (3 min) `docker compose up` → 9 contêineres rodando + um fluxo E2E local rápido.
3. (2 min) Console: cluster EKS ativo, node group (1/2/4), ECR com as 5 imagens, RDS×3, ElastiCache, DynamoDB, SQS.
4. (2 min) `kubectl get pods -A` (5 serviços em namespaces separados) + `kubectl get ingress`.
5. (3 min) Curls no DNS do NLB: criar chave → flag → regra → `/evaluate`.
6. (4 min) Carga com `hey` → `kubectl get hpa -w` mostrando réplicas subindo; mensagens em massa no SQS → analytics escalando → itens no DynamoDB.
7. (3 min) Desafios (limitações da LabRole, por que HPA-CPU e não KEDA) + fechamento.

### Relatório (.pdf)
- Nomes, RMs e usernames do Discord; link dos repositórios do grupo; link do vídeo (YouTube não listado).
- **+10 pts**: concluir a trilha do Google Cloud Skills Boost, deixar o badge público e colar o link.

### Limpeza (ordem importa!)
1. `kubectl delete ingress --all -A` e `kubectl delete svc ingress-nginx-controller -n ingress-nginx` (**remove o NLB**).
2. Deletar node group → deletar cluster EKS.
3. Deletar 3×RDS (sem snapshot final), ElastiCache, tabela DynamoDB, fila SQS, repos ECR.
4. Conferir no console EC2/VPC se não sobrou Load Balancer ou ENI órfã.

---

## Divisão sugerida por sessão de lab (~4h cada)
- **Sessão A (sem pressa, lab só p/ SQS):** Etapa 1 completa + demo local gravável.
- **Sessão B:** Etapas 2 e 3 (infra + cluster configurado).
- **Sessão C:** Etapas 4 e 5 (deploy + HPA + testes).
- **Sessão D:** gravação do vídeo + limpeza total.
