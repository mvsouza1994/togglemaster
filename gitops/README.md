# GitOps — manifestos do ToggleMaster

Esta pasta é o "repositório GitOps" do projeto (monorepo). Ela só tem manifestos Kubernetes. O ArgoCD observa esta pasta na branch `main` e aplica no cluster tudo o que mudar aqui.
**Ninguém faz `kubectl apply` dos serviços**: a mudança entra por commit.

```
gitops/
├── argocd/
│   ├── root.yaml                 # App of Apps (único apply manual, 1 vez)
│   └── apps/
│       ├── project.yaml          # AppProject "togglemaster" (restringe repo e namespaces)
│       ├── <servico>.yaml        # 5 Applications (auth, flag, targeting, evaluation, analytics)
│       ├── platform-ingress-nginx.yaml
│       └── platform-metrics-server.yaml
└── services/<servico>/           # Kustomize: namespace, configmap, deployment, service, ingress
    ├── deployment.yaml           # a tag da imagem é atualizada pelo CI
    ├── hpa.yaml                  # evaluation e analytics
    ├── db-migrate-job.yaml       # auth, flag e targeting: schema via hook PreSync
    └── schema.sql                # cópia de services/<servico>/db/init.sql
```

## Fluxo

1. Push em `services/<servico>/**` na `main` → pipeline `ci-<servico>`: testes, lint, SAST, SCA, build e scan da imagem.
2. A imagem é publicada com a tag `v1.0.0-<sha>`.
3. O job **GitOps** (`.github/workflows/_gitops.yml`) troca a imagem em `gitops/services/<servico>/deployment.yaml` e faz commit `deploy(<servico>): v1.0.0-<sha> [skip ci]`.
4. O ArgoCD detecta o commit e sincroniza automaticamente (`automated` + `prune` + `selfHeal`).

O commit do CI não dispara o CI de novo, por três motivos: só altera `gitops/` (fora dos `paths` dos workflows), leva `[skip ci]` e é feito com o `GITHUB_TOKEN`.

## Registry

A variável do repositório `REGISTRY` escolhe onde a imagem é publicada:

| `REGISTRY` | Imagem |
|---|---|
| `ghcr` (padrão) | `ghcr.io/mvsouza1994/togglemaster/<servico>:v1.0.0-<sha>` |
| `ecr` | `<conta>.dkr.ecr.us-east-1.amazonaws.com/togglemaster/<servico>:v1.0.0-<sha>` |

Para o ECR é preciso: `terraform apply`, os secrets `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_SESSION_TOKEN` e `REGISTRY=ecr`. Como o CI grava a URI completa no `deployment.yaml`, trocar de registry não exige mudar nenhum manifesto.

## Instalação (uma vez por cluster)

```bash
# 1. Secrets dos serviços (não ficam no git)
bash scripts/k8s-secrets.sh

# 2. ArgoCD
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd -n argocd --create-namespace --version 10.10.5

# 3. App of Apps: a partir daqui o ArgoCD cria todo o resto
kubectl apply -n argocd -f gitops/argocd/root.yaml

# UI
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
kubectl -n argocd port-forward svc/argocd-server 8080:443   # https://localhost:8080 (admin)
```

## Decisões

- **Sem `replicas`** nos Deployments com HPA (evaluation e analytics). Com o campo fixo, o `selfHeal` do ArgoCD desfaria o que o HPA escalou.
- **Schema do banco**: Job `PreSync` com `postgres:17-alpine`, que roda o SQL idempotente antes de cada sync. Substitui o `kubectl run psql` do `deploy.sh`.
- **SERVICE_API_KEY**: o Job do auth grava no banco o hash SHA-256 da chave que está no Secret. Assim não é mais preciso chamar `/admin/keys` depois do deploy (o "ovo e a galinha" da Fase 2).
- **Credenciais AWS**: nenhuma nos pods. evaluation e analytics usam a LabRole do node via IMDS (hop limit 2 no launch template do Terraform).
- **Segurança dos pods**: non-root (UID 10001), `readOnlyRootFilesystem`, sem capabilities, `seccomp RuntimeDefault`.
- **Secrets fora do git**: `scripts/k8s-secrets.sh` lê os outputs do Terraform e aplica direto no cluster.
- **ingress-nginx e metrics-server** como Applications Helm do ArgoCD, em vez de `kubectl apply` de URL.
  - Antes do `terraform destroy`, apague a Application `platform-ingress-nginx` para remover o NLB.
  - O projeto ingress-nginx foi descontinuado pela comunidade Kubernetes em 2026. Continua funcionando, mas não recebe mais correções.
