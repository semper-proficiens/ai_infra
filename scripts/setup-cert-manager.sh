#!/usr/bin/env bash
# setup-cert-manager.sh — Install cert-manager and configure ClusterIssuers
#
# Idempotent. Run after setup-vault-pki.sh for the vault-pki issuer.
# Requires: .cloudflare-creds with CF_API_TOKEN
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG="${KUBECONFIG:-${REPO_ROOT}/kubeconfig}"

if [[ -f "${REPO_ROOT}/.cloudflare-creds" ]]; then
  source "${REPO_ROOT}/.cloudflare-creds"
fi

if [[ -z "${CF_API_TOKEN:-}" ]]; then
  echo "ERROR: CF_API_TOKEN not set. Source .cloudflare-creds or export it."
  exit 1
fi

echo "==> Installing cert-manager..."
helm repo add jetstack https://charts.jetstack.io --force-update
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  -f "${REPO_ROOT}/k8s/cert-manager/helm-values.yaml" \
  --wait --timeout 3m

echo "==> Waiting for cert-manager webhooks to be ready..."
kubectl --kubeconfig="${KUBECONFIG}" wait deployment \
  --for=condition=Available \
  --timeout=60s \
  -n cert-manager \
  cert-manager cert-manager-webhook cert-manager-cainjector

echo "==> Creating Cloudflare API token secret..."
kubectl --kubeconfig="${KUBECONFIG}" create secret generic cloudflare-api-token \
  --from-literal=api-token="${CF_API_TOKEN}" \
  --namespace cert-manager \
  --dry-run=client -o yaml | kubectl --kubeconfig="${KUBECONFIG}" apply -f -

echo "==> Applying Let's Encrypt ClusterIssuers..."
kubectl --kubeconfig="${KUBECONFIG}" apply -f "${REPO_ROOT}/k8s/cert-manager/issuer-letsencrypt.yaml"

echo ""
echo "==> cert-manager ready. ClusterIssuers:"
kubectl --kubeconfig="${KUBECONFIG}" get clusterissuer

echo ""
echo "Note: vault-pki issuer requires setup-vault-pki.sh to be run first."
echo "      Run: make setup-vault-pki  (needs valid Teleport certs)"
