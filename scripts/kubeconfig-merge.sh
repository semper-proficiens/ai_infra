#!/usr/bin/env bash
# kubeconfig-merge.sh — merge homelab kubeconfig into ~/.kube/config
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "${SCRIPT_DIR}")"
NEW_KUBECONFIG="${REPO_ROOT}/kubeconfig"

if [[ ! -f "${NEW_KUBECONFIG}" ]]; then
  echo "Error: ${NEW_KUBECONFIG} not found. Run bootstrap-k3s.sh first."
  exit 1
fi

mkdir -p ~/.kube

if [[ -f ~/.kube/config ]]; then
  echo "==> Backing up existing kubeconfig to ~/.kube/config.bak"
  cp ~/.kube/config ~/.kube/config.bak
  KUBECONFIG="${NEW_KUBECONFIG}:${HOME}/.kube/config.bak" \
    kubectl config view --flatten > ~/.kube/config
  echo "==> Merged. Context 'homelab' is now available."
else
  cp "${NEW_KUBECONFIG}" ~/.kube/config
  echo "==> Copied kubeconfig to ~/.kube/config."
fi

echo "==> Switch context: kubectl config use-context homelab"
echo "==> Test:           kubectl get nodes"
