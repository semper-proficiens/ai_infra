#!/usr/bin/env bash
# setup-minio.sh — deploy distributed MinIO to k3s
#
# What it installs:
#   - minio namespace
#   - minio-credentials k8s Secret (root user + password)
#   - MinIO Helm release from charts.min.io (distributed, 4 pods, erasure coding EC:2)
#
# Fault tolerance:
#   4 drives across worker nodes. With 2 workers: 2 per node, cross-node HA.
#   With 1 worker: erasure coding only (drive fault tolerance, not node).
#   Survives loss of any 2 drives. Node failure → read-only until node recovers.
#
# Credentials:
#   Pass via .minio-creds file (same pattern as .deploy-creds) or env vars:
#     MINIO_ROOT_USER=<user>
#     MINIO_ROOT_PASSWORD=<password>
#   NEVER inline credentials in shell commands — write to a creds file first.
#
# After running, update Vault secret/starstalk with:
#   STORAGE_ENDPOINT   = http://minio.minio.svc.cluster.local:9000
#   STORAGE_ACCESS_KEY = <MINIO_ROOT_USER>
#   STORAGE_SECRET_KEY = <MINIO_ROOT_PASSWORD>
#   STORAGE_BUCKET     = starstalk-prod  (or as needed)
#
# Prerequisites:
#   - kubeconfig at ./kubeconfig (or set KUBECONFIG env var)
#   - helm + kubectl in PATH
#   - .minio-creds file or MINIO_ROOT_USER/MINIO_ROOT_PASSWORD env vars
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export KUBECONFIG="${KUBECONFIG:-${REPO_ROOT}/kubeconfig}"

# ── Helpers ───────────────────────────────────────────────────────────────────

require_cmd() {
  command -v "$1" &>/dev/null || { echo "Error: '$1' not found. Install it first."; exit 1; }
}

prompt_if_empty() {
  local var_name="$1" prompt_text="$2" is_secret="${3:-false}"
  if [[ -z "${!var_name:-}" ]]; then
    if [[ "${is_secret}" == "true" ]]; then
      read -rsp "${prompt_text}: " "${var_name}"
      echo
    else
      read -rp "${prompt_text}: " "${var_name}"
    fi
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

# ── Credentials ───────────────────────────────────────────────────────────────

# Load from .minio-creds if it exists (preferred — keeps creds out of shell history)
if [[ -f "${REPO_ROOT}/.minio-creds" ]]; then
  # shellcheck source=/dev/null
  source "${REPO_ROOT}/.minio-creds"
fi

prompt_if_empty MINIO_ROOT_USER     "MinIO root user (S3 access key, min 3 chars)"
prompt_if_empty MINIO_ROOT_PASSWORD "MinIO root password (S3 secret key, min 8 chars)" true

# ── Namespace ─────────────────────────────────────────────────────────────────

echo "==> Creating minio namespace..."
kubectl apply -f "${REPO_ROOT}/k8s/minio/namespace.yaml"

# ── Credentials secret ────────────────────────────────────────────────────────

echo "==> Creating/refreshing minio-credentials secret..."
kubectl create secret generic minio-credentials \
  --from-literal=rootUser="${MINIO_ROOT_USER}" \
  --from-literal=rootPassword="${MINIO_ROOT_PASSWORD}" \
  --namespace minio \
  --dry-run=client -o yaml | kubectl apply -f -

# ── Helm repo ─────────────────────────────────────────────────────────────────

echo "==> Adding MinIO Helm repo..."
helm repo add minio-official https://charts.min.io/ 2>/dev/null || true
helm repo update minio-official

# ── MinIO ─────────────────────────────────────────────────────────────────────

echo "==> Deploying MinIO (distributed, 4 pods)..."
helm_install_or_upgrade minio minio-official/minio \
  --namespace minio \
  -f "${REPO_ROOT}/helm/minio/values.yaml" \
  --wait --timeout 5m

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "==> MinIO is up!"
echo ""
echo "    Pods:"
kubectl get pods -n minio -l app=minio
echo ""
echo "    S3 endpoint (in-cluster): http://minio.minio.svc.cluster.local:9000"
echo "    Console    (in-cluster): http://minio.minio.svc.cluster.local:9001"
echo ""
echo "    ┌─────────────────────────────────────────────────────────────────┐"
echo "    │  ACTION REQUIRED: update Vault secret/starstalk with:           │"
echo "    │    STORAGE_ENDPOINT   = http://minio.minio.svc.cluster.local:9000 │"
echo "    │    STORAGE_ACCESS_KEY = (your MINIO_ROOT_USER)                  │"
echo "    │    STORAGE_SECRET_KEY = (your MINIO_ROOT_PASSWORD)              │"
echo "    │    STORAGE_BUCKET     = starstalk-prod                          │"
echo "    └─────────────────────────────────────────────────────────────────┘"
echo ""
echo "    Console port-forward:"
echo "      kubectl port-forward svc/minio-console -n minio 9001:9001"
echo "      Then open: http://localhost:9001"
echo ""
