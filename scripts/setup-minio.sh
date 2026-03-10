#!/usr/bin/env bash
# setup-minio.sh — deploy distributed MinIO to k3s
#
# What it installs:
#   - minio namespace
#   - minio-credentials k8s Secret (root user + password)
#   - Bitnami MinIO Helm release (distributed, 4 pods, erasure coding EC:2)
#
# Fault tolerance:
#   4 drives across 2 k3s workers (2 per node, ssj1 + ssj2).
#   Survives loss of any 2 drives. Node failure → read-only until node recovers.
#
# After running, update Vault secret/starstalk with:
#   STORAGE_ENDPOINT  = http://minio.minio.svc.cluster.local:9000
#   STORAGE_ACCESS_KEY = <the root user you set here>
#   STORAGE_SECRET_KEY = <the root password you set here>
#   STORAGE_BUCKET     = starstalk-media  (or whatever bucket you create)
#
# Prerequisites:
#   - kubeconfig at ./kubeconfig (or set KUBECONFIG env var)
#   - helm + kubectl in PATH
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

prompt_if_empty MINIO_ROOT_USER     "MinIO root user (S3 access key, min 3 chars)"
prompt_if_empty MINIO_ROOT_PASSWORD "MinIO root password (S3 secret key, min 8 chars)" true

# ── Namespace ─────────────────────────────────────────────────────────────────

echo "==> Creating minio namespace..."
kubectl apply -f "${REPO_ROOT}/k8s/minio/namespace.yaml"

# ── Credentials secret ────────────────────────────────────────────────────────

echo "==> Creating/refreshing minio-credentials secret..."
kubectl create secret generic minio-credentials \
  --from-literal=root-user="${MINIO_ROOT_USER}" \
  --from-literal=root-password="${MINIO_ROOT_PASSWORD}" \
  --namespace minio \
  --dry-run=client -o yaml | kubectl apply -f -

# ── Helm repo ─────────────────────────────────────────────────────────────────

echo "==> Adding Bitnami Helm repo..."
helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
helm repo update bitnami

# ── MinIO ─────────────────────────────────────────────────────────────────────

echo "==> Deploying MinIO (distributed, 4 pods)..."
helm_install_or_upgrade minio bitnami/minio \
  --namespace minio \
  -f "${REPO_ROOT}/helm/minio/values.yaml" \
  --wait --timeout 5m

# ── Create default bucket ─────────────────────────────────────────────────────

BUCKET="${MINIO_BUCKET:-starstalk-media}"
echo "==> Waiting for MinIO pods to be ready before creating bucket..."
kubectl rollout status statefulset/minio -n minio --timeout=5m

echo "==> Creating bucket: ${BUCKET}"
kubectl run minio-mc-init \
  --image=minio/mc:latest \
  --restart=Never \
  --rm \
  --attach \
  --namespace=minio \
  --env="MC_HOST_local=http://${MINIO_ROOT_USER}:${MINIO_ROOT_PASSWORD}@minio.minio.svc.cluster.local:9000" \
  -- mc mb --ignore-existing "local/${BUCKET}" 2>/dev/null || \
  echo "    (bucket creation skipped — run manually if needed)"

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "==> MinIO is up!"
echo ""
echo "    Pods:"
kubectl get pods -n minio -l app.kubernetes.io/name=minio
echo ""
echo "    S3 endpoint (in-cluster): http://minio.minio.svc.cluster.local:9000"
echo "    Console    (in-cluster): http://minio.minio.svc.cluster.local:9001"
echo "    Default bucket:          ${BUCKET}"
echo ""
echo "    ┌─────────────────────────────────────────────────────────────┐"
echo "    │  ACTION REQUIRED: update Vault secret/starstalk with:       │"
echo "    │    STORAGE_ENDPOINT  = http://minio.minio.svc.cluster.local:9000 │"
echo "    │    STORAGE_ACCESS_KEY = ${MINIO_ROOT_USER}                  │"
echo "    │    STORAGE_SECRET_KEY = (the password you just set)         │"
echo "    │    STORAGE_BUCKET     = ${BUCKET}                           │"
echo "    └─────────────────────────────────────────────────────────────┘"
echo ""
echo "    Console port-forward:"
echo "      kubectl port-forward svc/minio -n minio 9001:9001"
echo "      Then open: http://localhost:9001"
echo ""
