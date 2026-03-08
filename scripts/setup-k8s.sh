#!/usr/bin/env bash
# setup-k8s.sh — bootstrap the full k8s stack on a fresh k3s cluster
#
# Run this once after `make bootstrap-k3s`. Idempotent — safe to re-run.
#
# What it installs:
#   1. CloudNativePG operator  (PostgreSQL HA)
#   2. kube-prometheus-stack   (Prometheus + Grafana + Alertmanager)
#   3. starstalk namespace + secrets
#   4. PostgreSQL Cluster CR
#   5. starstalk backend (Helm)
#
# Prerequisites:
#   - kubeconfig at ./kubeconfig (written by make bootstrap-k3s)
#   - .deploy-creds with VAULT_ROLE_ID + VAULT_SECRET_ID
#   - GRAFANA_PASSWORD env var or prompt
#   - PG_SUPERUSER_PASSWORD + PG_APP_PASSWORD env vars or prompt
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export KUBECONFIG="${KUBECONFIG:-${REPO_ROOT}/kubeconfig}"

# Load deploy creds
if [[ -f "${REPO_ROOT}/.deploy-creds" ]]; then
  # shellcheck source=/dev/null
  source "${REPO_ROOT}/.deploy-creds"
fi

# ── Helpers ───────────────────────────────────────────────────────────────────

require_cmd() {
  command -v "$1" &>/dev/null || { echo "Error: '$1' not found. Install it first."; exit 1; }
}

prompt_if_empty() {
  local var_name="$1" prompt_text="$2"
  if [[ -z "${!var_name:-}" ]]; then
    read -rsp "${prompt_text}: " "${var_name}"
    echo
    export "${var_name?}"
  fi
}

helm_install_or_upgrade() {
  local release="$1" chart="$2"; shift 2
  echo "==> Helm: ${release} (${chart})"
  helm upgrade --install "${release}" "${chart}" "$@"
}

# ── Preflight ─────────────────────────────────────────────────────────────────

require_cmd kubectl
require_cmd helm

echo "==> Checking cluster access..."
kubectl cluster-info --request-timeout=10s

# ── Gather secrets ────────────────────────────────────────────────────────────

: "${VAULT_ROLE_ID:?VAULT_ROLE_ID must be set (in .deploy-creds or env)}"
: "${VAULT_SECRET_ID:?VAULT_SECRET_ID must be set (in .deploy-creds or env)}"

prompt_if_empty GRAFANA_PASSWORD    "Grafana admin password"
prompt_if_empty PG_SUPERUSER_PASSWORD "PostgreSQL superuser (postgres) password"
prompt_if_empty PG_APP_PASSWORD       "PostgreSQL app user (starstalk) password"

IMAGE_TAG="${IMAGE_TAG:-latest}"

# ── Helm repos ────────────────────────────────────────────────────────────────

echo "==> Adding Helm repos..."
helm repo add cnpg          https://cloudnative-pg.github.io/charts         2>/dev/null || true
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update

# ── Namespaces ────────────────────────────────────────────────────────────────

echo "==> Creating namespaces..."
kubectl apply -f "${REPO_ROOT}/k8s/starstalk/namespace.yaml"
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace cnpg-system --dry-run=client -o yaml | kubectl apply -f -

# ── CloudNativePG operator ────────────────────────────────────────────────────

echo "==> Installing CloudNativePG operator..."
helm_install_or_upgrade cloudnative-pg cnpg/cloudnative-pg \
  --namespace cnpg-system \
  --wait

# ── kube-prometheus-stack ─────────────────────────────────────────────────────

echo "==> Installing kube-prometheus-stack..."
helm_install_or_upgrade kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set "grafana.adminPassword=${GRAFANA_PASSWORD}" \
  -f "${REPO_ROOT}/k8s/monitoring/prometheus-stack-values.yaml" \
  --wait --timeout 5m

# ── Kubernetes secrets ────────────────────────────────────────────────────────

echo "==> Creating/refreshing Kubernetes secrets..."

# Vault AppRole creds (used by the starstalk backend pod)
kubectl create secret generic starstalk-vault \
  --from-literal=VAULT_ROLE_ID="${VAULT_ROLE_ID}" \
  --from-literal=VAULT_SECRET_ID="${VAULT_SECRET_ID}" \
  --namespace starstalk \
  --dry-run=client -o yaml | kubectl apply -f -

# PostgreSQL credentials (used by CloudNativePG)
kubectl create secret generic starstalk-pg-superuser \
  --from-literal=username=postgres \
  --from-literal=password="${PG_SUPERUSER_PASSWORD}" \
  --namespace starstalk \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic starstalk-pg-app \
  --from-literal=username=starstalk \
  --from-literal=password="${PG_APP_PASSWORD}" \
  --namespace starstalk \
  --dry-run=client -o yaml | kubectl apply -f -

# ── PostgreSQL cluster ────────────────────────────────────────────────────────

echo "==> Applying PostgreSQL cluster..."
kubectl apply -f "${REPO_ROOT}/k8s/cloudnativepg/cluster.yaml"

echo "==> Waiting for PostgreSQL primary to be ready (up to 5m)..."
kubectl wait cluster/starstalk-pg \
  --for=condition=Ready \
  --namespace starstalk \
  --timeout=300s

# ── starstalk backend (Helm) ──────────────────────────────────────────────────

echo "==> Deploying starstalk backend..."
helm_install_or_upgrade starstalk \
  "${REPO_ROOT}/helm/starstalk" \
  --namespace starstalk \
  --set "image.tag=${IMAGE_TAG}" \
  -f "${REPO_ROOT}/helm/starstalk/values-homelab.yaml" \
  --wait

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "==> Stack is up!"
echo ""
echo "    Nodes:"
kubectl get nodes -o wide
echo ""
echo "    Pods (starstalk):"
kubectl get pods -n starstalk
echo ""
echo "    PostgreSQL cluster:"
kubectl get cluster -n starstalk
echo ""
echo "    Grafana:   http://grafana.starstalk.io  (or kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80)"
echo "    Backend:   http://api.starstalk.io"
echo ""
echo "    Next: configure DB_HOST in values-homelab.yaml → starstalk-pg-rw.starstalk.svc"
echo "    Then: data migration from starstalk-postgres VM — see docs/migration.md"
