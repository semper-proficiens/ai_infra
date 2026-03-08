#!/usr/bin/env bash
# setup-k8s-dev.sh — bootstrap the dev stack on the k3s cluster
#
# Run once after setup-k8s.sh (which installs the operators).
# Idempotent — safe to re-run.
#
# What it creates:
#   - starstalk-dev namespace
#   - Vault + PostgreSQL secrets (dev)
#   - CloudNativePG cluster (1 instance, 5Gi)
#   - starstalk backend Helm release (1 replica, api-dev.starstalk.io)
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export KUBECONFIG="${KUBECONFIG:-${REPO_ROOT}/kubeconfig}"

if [[ -f "${REPO_ROOT}/.deploy-creds" ]]; then
  # shellcheck source=/dev/null
  source "${REPO_ROOT}/.deploy-creds"
fi

# ── Helpers ───────────────────────────────────────────────────────────────────

prompt_if_empty() {
  local var_name="$1" prompt_text="$2"
  if [[ -z "${!var_name:-}" ]]; then
    read -rsp "${prompt_text}: " "${var_name}"
    echo
    export "${var_name?}"
  fi
}

# ── Preflight ─────────────────────────────────────────────────────────────────

command -v kubectl &>/dev/null || { echo "Error: kubectl not found"; exit 1; }
command -v helm    &>/dev/null || { echo "Error: helm not found"; exit 1; }
kubectl cluster-info --request-timeout=10s

# ── Gather secrets ────────────────────────────────────────────────────────────

: "${VAULT_ROLE_ID:?VAULT_ROLE_ID must be set (in .deploy-creds or env)}"
: "${VAULT_SECRET_ID:?VAULT_SECRET_ID must be set (in .deploy-creds or env)}"

prompt_if_empty DEV_PG_SUPERUSER_PASSWORD "Dev PostgreSQL superuser password"
prompt_if_empty DEV_PG_APP_PASSWORD       "Dev PostgreSQL app user (starstalk) password"

IMAGE_TAG="${IMAGE_TAG:-dev}"

# ── Namespace ─────────────────────────────────────────────────────────────────

echo "==> Creating starstalk-dev namespace..."
kubectl apply -f "${REPO_ROOT}/k8s/starstalk/namespace-dev.yaml"

# ── Kubernetes secrets ────────────────────────────────────────────────────────

echo "==> Creating/refreshing secrets in starstalk-dev..."

kubectl create secret generic starstalk-vault \
  --from-literal=VAULT_ROLE_ID="${VAULT_ROLE_ID}" \
  --from-literal=VAULT_SECRET_ID="${VAULT_SECRET_ID}" \
  --namespace starstalk-dev \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic starstalk-pg-dev-superuser \
  --from-literal=username=postgres \
  --from-literal=password="${DEV_PG_SUPERUSER_PASSWORD}" \
  --namespace starstalk-dev \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic starstalk-pg-dev-app \
  --from-literal=username=starstalk \
  --from-literal=password="${DEV_PG_APP_PASSWORD}" \
  --namespace starstalk-dev \
  --dry-run=client -o yaml | kubectl apply -f -

# ── PostgreSQL cluster (dev) ──────────────────────────────────────────────────

echo "==> Applying dev PostgreSQL cluster..."
kubectl apply -f "${REPO_ROOT}/k8s/cloudnativepg/cluster-dev.yaml"

echo "==> Waiting for dev PostgreSQL to be ready (up to 3m)..."
kubectl wait cluster/starstalk-pg-dev \
  --for=condition=Ready \
  --namespace starstalk-dev \
  --timeout=180s

# ── starstalk backend (dev Helm release) ──────────────────────────────────────

echo "==> Deploying starstalk backend (dev)..."
helm upgrade --install starstalk-dev \
  "${REPO_ROOT}/helm/starstalk" \
  --namespace starstalk-dev \
  --set "image.tag=${IMAGE_TAG}" \
  -f "${REPO_ROOT}/helm/starstalk/values-dev.yaml" \
  --wait

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "==> Dev stack is up!"
echo ""
kubectl get pods -n starstalk-dev
echo ""
echo "    Backend:  https://api-dev.starstalk.io"
echo "    DB (rw):  starstalk-pg-dev-rw.starstalk-dev.svc.cluster.local:5432"
echo ""
echo "    To redeploy after a code change:"
echo "      git checkout dev && git push origin dev"
echo ""
echo "    To promote dev → prod:"
echo "      git checkout main && git merge dev && git tag v<X.Y.Z> && git push origin main --tags"
