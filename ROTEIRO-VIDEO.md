# Roteiro do vídeo: Fase 3 (até 20 min)

Os 4 blocos que o PDF pede, em ordem. Os comandos rodam na raiz do repositório.

| Bloco | O que mostrar | Tempo |
|---|---|---|
| 0 | Preparação (antes de gravar) | — |
| 1 | IaC: Terraform plan/apply e recursos na AWS | ~5 min |
| 2 | DevSecOps: pipeline falhando no scan, correção, pipeline passando | ~6 min |
| 3 | GitOps: o CI atualizando a tag no `gitops/` | ~2 min |
| 4 | ArgoCD: detectando a mudança e sincronizando | ~4 min |

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

1. Mostre a estrutura `terraform/` e o `versions.tf` (backend S3).
2. Mostre o `terraform plan` rodando:
   - **Pelo GitHub:** Actions → terraform → Run workflow → `plan` (ou `apply`, se for subir do zero na gravação).
   - **Ou local:** `cd terraform && terraform init && terraform plan`
3. Mostre o resultado na AWS: VPC com subnets públicas e privadas, cluster EKS `togglemaster`,
   3 RDS, Redis, tabela DynamoDB, fila SQS e 5 repositórios ECR.
   Pelo terminal: `terraform -chdir=terraform output`

---

## 2. DevSecOps: pipeline falhando e passando

**Falar:** cada serviço tem um pipeline com 4 estágios encadeados (`needs:`). Um só roda se o anterior passou:
Build & Unit Test → Lint (golangci-lint / flake8) → Security Scan (SAST: gosec / bandit; SCA: Trivy fs)
→ Docker Build, Scan & Push. **Vulnerabilidade CRITICAL bloqueia o pipeline.**

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
Use (botão **Squash and merge**, ou `gh pr merge --squash --delete-branch`).

---

## 3. GitOps: o CI atualizando a tag

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
