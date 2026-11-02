#!/bin/bash
# Tudo o que precisa acontecer no cluster depois do "terraform apply". Idempotente:
# pode rodar de novo a qualquer momento (ex.: a cada recriacao do ambiente).
#
#   1. kubeconfig do cluster
#   2. Secrets dos 5 servicos (scripts/k8s-secrets.sh, a partir dos outputs do Terraform)
#   3. ArgoCD via Helm
#   4. App of Apps (gitops/argocd/root.yaml): o ArgoCD cria todo o resto a partir do git
#
# Uso: bash scripts/cluster-bootstrap.sh   (roda tambem no workflow terraform, apos o apply)
set -euo pipefail
cd "$(dirname "$0")/.."

ARGOCD_CHART_VERSION="${ARGOCD_CHART_VERSION:-10.10.5}"
REGION=$(terraform -chdir=terraform output -raw region)
CLUSTER=$(terraform -chdir=terraform output -raw cluster_name)

echo "==> kubeconfig ($CLUSTER)"
aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" >/dev/null
kubectl wait --for=condition=Ready nodes --all --timeout=10m

echo "==> Secrets dos servicos"
bash scripts/k8s-secrets.sh

echo "==> ArgoCD (chart $ARGOCD_CHART_VERSION)"
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update argo >/dev/null
helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace \
  --version "$ARGOCD_CHART_VERSION" --wait --timeout 10m

echo "==> App of Apps"
kubectl apply -n argocd -f gitops/argocd/root.yaml

cat <<'EOF'

Pronto. O ArgoCD vai criar as Applications e sincronizar os servicos (2-5 min).
  Senha do admin: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
  UI:             kubectl -n argocd port-forward svc/argocd-server 8080:443   ->  https://localhost:8080 (usuario admin)
  Status:         kubectl get applications -n argocd
EOF
