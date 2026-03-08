#!/usr/bin/env bash
# install-k8s-tools.sh — install kubectl + helm on a node
#
# Runs ON the remote node (sent via run-on-node.sh).
# Idempotent — skips tools that are already installed.
#
set -euo pipefail

KUBECTL_VERSION="v1.31.0"
HELM_VERSION="v3.16.0"

# ── kubectl ───────────────────────────────────────────────────────────────────

if command -v kubectl &>/dev/null; then
  echo "==> kubectl already installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
else
  echo "==> Installing kubectl ${KUBECTL_VERSION}..."
  curl -sSfLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
  install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  rm kubectl
  echo "==> kubectl installed: $(kubectl version --client --short 2>/dev/null || true)"
fi

# ── helm ──────────────────────────────────────────────────────────────────────

if command -v helm &>/dev/null; then
  echo "==> helm already installed: $(helm version --short)"
else
  echo "==> Installing helm ${HELM_VERSION}..."
  curl -sSfL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | \
    DESIRED_VERSION="${HELM_VERSION}" bash
  echo "==> helm installed: $(helm version --short)"
fi

echo "==> k8s tools ready."
