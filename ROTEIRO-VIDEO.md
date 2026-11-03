# Roteiro do vídeo: Fase 3 (até 20 min)

Passo a passo para apresentar. Cada bloco cobre um item dos entregáveis do PDF.
Os comandos rodam na raiz do repositório.

| Item do PDF | Onde no roteiro | Tempo |
|---|---|---|
| — | 0. Preparação (antes de gravar) | — |
| **Código fonte:** Terraform bem estruturado e componentizado | 1. IaC (1.1) | ~2 min |
| **Vídeo, IaC:** `terraform plan` e `apply` ou o resultado na AWS | 1. IaC (1.2 e 1.3) | ~3 min |
| **Código fonte:** workflows do GitHub Actions com DevSecOps | 2. DevSecOps (2.0) | ~2 min |
| **Vídeo, DevSecOps:** pipeline falhando no passo de segurança, correção, passando | 2. DevSecOps (2.1 a 2.3) | ~5 min |
| **Código fonte:** manifestos Kubernetes ajustados para GitOps | 3. GitOps (3.0) | ~1 min |
| **Vídeo, GitOps:** pipeline atualizando a tag no repositório GitOps | 3. GitOps (3.1) | ~2 min |
| **Vídeo, ArgoCD:** detectando a mudança e sincronizando sozinho | 4. ArgoCD | ~4 min |

---

## 0. Preparação (fora da gravação)

1. **Start Lab** no AWS Academy, depois AWS Details → AWS CLI → Show. Cole o bloco no `[default]` do `~/.aws/credentials`.
2. Atualize os secrets do GitHub: `bash scripts/gh-aws-secrets.sh`
3. Infra no ar? Se não estiver: `gh workflow run terraform.yml -f action=apply` (~20 min; já instala o ArgoCD e as apps).
4. kubectl e ArgoCD:
   ```bash
   aws eks update-kubeconfig --name togglemaster --region us-east-1
   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
   kubectl -n argocd port-forward svc/argocd-server 8443:443     # https://localhost:8443, usuário admin
   ```
   Se o lab ficou parado, os nodes voltam sozinhos após o Start Lab (2-3 min): `kubectl get nodes` até `Ready`.
5. Confira que está tudo verde: `kubectl get applications -n argocd` (8 apps Synced/Healthy).
6. Deixe abertas no navegador:
   - Actions: https://github.com/mvsouza1994/togglemaster/actions
   - ArgoCD: https://localhost:8443
   - Console AWS (botão "AWS" do Learner Lab): EKS, VPC, RDS

---

## 1. IaC: Terraform

**Falar:** a infra que na Fase 2 era criada à mão agora é código. Módulos em `terraform/modules/`
(network, eks, rds, elasticache, dynamodb, sqs, ecr), state remoto no S3 com `use_lockfile`,
LabRole lida por `data "aws_iam_role"` e nenhuma role ou policy criada.

### 1.1 Código (mostrar no editor ou no GitHub)

| Arquivo | O que apontar |
|---|---|
| `terraform/main.tf` | só chama os módulos; `data "aws_iam_role" "lab"` lê a LabRole |
| `terraform/modules/` | um módulo por responsabilidade: network, eks, rds, elasticache, dynamodb, sqs, ecr |
| `terraform/modules/network/main.tf` | VPC, 2 subnets públicas e 2 privadas, Internet Gateway, NAT, route tables |
| `terraform/modules/eks/main.tf` | cluster e node group com `role_arn` = LabRole; launch template com `http_put_response_hop_limit = 2` (pods usam a LabRole, sem credenciais em arquivo) |
| `terraform/modules/rds/main.tf` | 3 PostgreSQL; senha com `random_password` guardada no Secrets Manager (nada em texto puro) |
| `terraform/versions.tf` | backend S3 com `use_lockfile = true` (state remoto, com lock) |
| `.github/workflows/terraform.yml` | o próprio Terraform roda pelo GitHub Actions |

### 1.2 `terraform plan` / `apply` rodando

- **Pelo GitHub (recomendado):** Actions → **terraform** → Run workflow → `plan`.
  Abra o passo **terraform plan** e mostre o resumo. Com a infra já no ar, aparece "No changes":
  o código e a AWS estão iguais.
- Para mostrar o **apply** criando tudo, grave um `apply` do zero (~20 min, dá para cortar a espera na edição)
  ou mostre um run antigo de `apply` na lista do workflow.
- **Ou local:** `cd terraform && terraform init && terraform plan`

### 1.3 Resultado na AWS

No console (botão "AWS" do Learner Lab): VPC `togglemaster` com subnets públicas e privadas,
cluster EKS `togglemaster`, 3 RDS, Redis, tabela DynamoDB `ToggleMasterAnalytics`, fila SQS
`togglemaster-events` e 5 repositórios ECR. Pelo terminal: `terraform -chdir=terraform output`

---

## 2. DevSecOps: pipeline falhando e passando

**Falar:** cada serviço tem um pipeline com 4 estágios encadeados (`needs:`). Um só roda se o anterior passou:
Build & Unit Test → Lint (golangci-lint / flake8) → Security Scan (SAST: gosec / bandit; SCA: Trivy fs)
→ Docker Build, Scan & Push. **Vulnerabilidade CRITICAL bloqueia o pipeline.**

### 2.0 Código (mostrar no editor ou no GitHub)

| Arquivo | O que apontar |
|---|---|
| `.github/workflows/ci-flag.yml` (e os outros 4 `ci-*.yml`) | gatilhos em `pull_request` e `push` na main, com filtro de `paths`; encadeia ci → image → gitops |
| `.github/workflows/_ci-python.yml` / `_ci-go.yml` | jobs **Build & Unit Test** → **Lint** (flake8 / golangci-lint) → **Security Scan**: SAST (bandit / gosec) e SCA (Trivy fs); o passo `--severity CRITICAL --exit-code 1` é a **regra de bloqueio** |
| `.github/workflows/_image.yml` | build da imagem, **Trivy na imagem** (CRITICAL bloqueia), login no registry e push com tag `v1.0.0-<sha>` |
| `.github/workflows/_gitops.yml` | `yq` troca a imagem no `deployment.yaml` e faz commit `[skip ci]` |

A quebra usa uma vulnerabilidade **real**: `certifi 2026.7.22` tem a GHSA-6q48-6c7w-9gw2 (CRITICAL,
certificados raiz da emSign comprometidos). A correção é `2026.10.18`.

**Onde fica o ajuste:** `services/flag-service/requirements.txt`, linha 3.

```diff
- certifi==2026.10.18
+ certifi==2026.7.22
```

### 2.1 Quebrar

```bash
git switch main && git pull
git switch -c demo/vuln
sed -i 's/^certifi==.*/certifi==2026.7.22/' services/flag-service/requirements.txt
git diff                                   # mostre a linha alterada
git commit -am "chore(flag): downgrade do certifi"
git push -u origin demo/vuln
gh pr create --fill
```

No PR (aba Checks) ou em Actions → ci-flag:
- ✅ Build & Unit Test (pytest)
- ✅ Lint / Static Analysis (flake8)
- ❌ Security Scan: passa no **SAST - bandit** e falha em **SCA - Trivy fs (CRITICAL bloqueia o pipeline)**
- O job **Docker Build, Scan & Push** nem roda.

Abra o passo que falhou e mostre a tabela do Trivy: `certifi │ GHSA-6q48-6c7w-9gw2 │ CRITICAL │ 2026.10.18`.

### 2.2 Corrigir

```bash
sed -i 's/^certifi==.*/certifi==2026.10.18/' services/flag-service/requirements.txt
git commit -am "fix(flag): certifi 2026.10.18 (GHSA-6q48-6c7w-9gw2)"
git push
```

O PR roda de novo e fica verde. Em PR o job de imagem faz build e scan, mas **não publica**: a publicação só acontece na `main`.

### 2.3 Merge

Faça o merge do PR. O merge gera um commit novo na `main`, e portanto uma tag de imagem nova.
Use o botão **Squash and merge** ou `gh pr merge --squash --delete-branch`.

---

## 3. GitOps: o CI atualizando a tag

### 3.0 Código (mostrar no editor ou no GitHub)

| Arquivo | O que apontar |
|---|---|
| `gitops/services/<servico>/` | só manifestos (Kustomize): namespace, configmap, deployment, service, ingress, hpa |
| `gitops/services/flag-service/deployment.yaml` | a linha `image:` é a única que o CI altera; sem `replicas` onde há HPA |
| `gitops/services/flag-service/db-migrate-job.yaml` | schema do banco via hook **PreSync** (substitui o `kubectl run psql` da Fase 2) |
| `gitops/argocd/root.yaml` + `gitops/argocd/apps/` | App of Apps: uma Application por serviço, `automated` com `prune` e `selfHeal` |
| Secrets | não estão no git: `scripts/k8s-secrets.sh` lê os outputs do Terraform e cria direto no cluster |

### 3.1 O pipeline atualizando a tag

Na `main`, o `ci-flag` roda os 4 estágios e depois o job **gitops**:

1. A imagem é publicada com a tag `v1.0.0-<sha curto>`.
2. O job gitops altera `gitops/services/flag-service/deployment.yaml` e faz o commit
   `deploy(flag-service): v1.0.0-<sha> [skip ci]`.

Mostre:
- O job gitops no Actions.
- O commit em https://github.com/mvsouza1994/togglemaster/commits/main/gitops (abra o diff: só a linha `image:` muda).

**Falar:** ninguém roda `kubectl apply`. O CI não tem acesso ao cluster; ele só escreve no git.
O `[skip ci]` e o filtro de `paths` impedem que esse commit dispare o pipeline de novo.

---

## 4. ArgoCD: sincronização automática

1. No ArgoCD, abra a app **flag-service**. Em até 3 minutos ela detecta o commit, fica
   **OutOfSync** por um instante e sincroniza sozinha (`automated` + `prune` + `selfHeal`).
   Para não esperar: botão **Refresh**.
2. Mostre o Job `flag-db-migrate` (hook PreSync) rodando antes, os pods novos subindo e os antigos saindo.
3. Confira a tag nova no cluster:
   ```bash
   kubectl get deploy flag-service -n flags -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
   ```
4. Volte à tela inicial do ArgoCD: os **5 microsserviços** Synced/Healthy.
5. **(Extra) selfHeal:** uma mudança feita fora do git é desfeita sozinha:
   ```bash
   kubectl scale deploy auth-service -n auth --replicas=0
   ```
   Na app auth-service os pods somem e voltam em poucos segundos.
6. **(Extra) Sistema funcionando** pelo load balancer:
   ```bash
   LB=$(kubectl get svc -n ingress-nginx -o jsonpath='{.items[?(@.spec.type=="LoadBalancer")].status.loadBalancer.ingress[0].hostname}')
   KEY=$(kubectl get secret evaluation-secrets -n evaluation -o jsonpath='{.data.SERVICE_API_KEY}' | base64 -d)
   curl -s -X POST http://$LB/flags -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
     -d '{"name":"demo-video","is_enabled":true}'
   curl -s -X POST http://$LB/rules -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
     -d '{"flag_name":"demo-video","is_enabled":true,"rules":{"type":"PERCENTAGE","value":50}}'
   for u in user-1 user-2 user-3 user-4; do curl -s "http://$LB/evaluate?user_id=$u&flag_name=demo-video"; echo; done
   aws dynamodb scan --table-name ToggleMasterAnalytics --select COUNT
   ```
   (Se a flag já existir, use outro nome.)

---

## Depois de gravar

```bash
gh workflow run terraform.yml -f action=destroy    # apaga apps/NLB e depois a infra
```

## Se algo der errado

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| Pipeline falha em "Credenciais AWS" ou com `ExpiredToken` | sessão do lab expirou | Start Lab, colar credenciais, `bash scripts/gh-aws-secrets.sh`, re-run |
| Outro serviço falha no Trivy CRITICAL sem você ter mudado nada | saiu uma CVE nova numa dependência | ver o pacote e a versão corrigida na tabela do Trivy e atualizar o `requirements.txt` / `go.mod` |
| ArgoCD não muda após o commit de deploy | polling de 3 min | botão **Refresh** na app |
| `kubectl` sem acesso | kubeconfig de outro cluster/conta | `aws eks update-kubeconfig --name togglemaster --region us-east-1` |
| Port-forward: "address already in use" | porta ocupada | usar outra porta: `8444:443` |
