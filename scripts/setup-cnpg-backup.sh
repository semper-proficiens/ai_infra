#!/usr/bin/env bash
# setup-cnpg-backup.sh — Configure CNPG continuous backup to k8s MinIO
#
# Creates the backup bucket and k8s credentials secret, then applies
# the updated cluster.yaml. Idempotent.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG="${KUBECONFIG:-${REPO_ROOT}/kubeconfig}"
BUCKET="starstalk-pg-backups"
MINIO_SVC="http://minio.minio.svc.cluster.local:9000"

# Load MinIO credentials (written by setup-minio.sh)
if [[ -f "${REPO_ROOT}/.minio-creds" ]]; then
  source "${REPO_ROOT}/.minio-creds"
else
  echo "ERROR: .minio-creds not found. Run scripts/setup-minio.sh first."
  exit 1
fi

echo "==> Creating MinIO backup bucket: ${BUCKET}..."
kubectl --kubeconfig="${KUBECONFIG}" exec -n minio minio-0 -- \
  mc alias set local "${MINIO_SVC}" "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}" \
  --api S3v4 > /dev/null

kubectl --kubeconfig="${KUBECONFIG}" exec -n minio minio-0 -- \
  mc mb --ignore-existing "local/${BUCKET}"

# Versioning so old WAL files are retained for recovery
kubectl --kubeconfig="${KUBECONFIG}" exec -n minio minio-0 -- \
  mc version enable "local/${BUCKET}" > /dev/null

echo "==> Creating backup credentials secret in starstalk namespace..."
kubectl --kubeconfig="${KUBECONFIG}" create secret generic starstalk-pg-backup-s3 \
  --from-literal=ACCESS_KEY_ID="${MINIO_ROOT_USER}" \
  --from-literal=ACCESS_SECRET_KEY="${MINIO_ROOT_PASSWORD}" \
  --namespace starstalk \
  --dry-run=client -o yaml | kubectl --kubeconfig="${KUBECONFIG}" apply -f -

echo "==> Applying updated CNPG cluster.yaml (adds backup spec)..."
kubectl --kubeconfig="${KUBECONFIG}" apply -f "${REPO_ROOT}/k8s/cloudnativepg/cluster.yaml"

echo "==> Waiting for CNPG to acknowledge backup config..."
sleep 10
kubectl --kubeconfig="${KUBECONFIG}" get cluster starstalk-pg -n starstalk \
  -o jsonpath='{.status.conditions[?(@.type=="ContinuousArchiving")]}' | python3 -c "
import sys, json
cond = json.load(sys.stdin)
print('ContinuousArchiving:', cond.get('status'), '--', cond.get('message',''))
" 2>/dev/null || echo "(archiving status not yet available — check in ~60s)"

echo ""
echo "==> CNPG backup configured. Schedule a base backup now:"
echo "    make cnpg-backup-now"
