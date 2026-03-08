#!/usr/bin/env bash
# sync-tbot-identity.sh — pull fresh tbot identity from k8s Secret to WSL2
#
# Run after tbot k8s deployment is up, or on WSL2 startup to refresh local
# identity file used by tsh/make ssh/make status.
#
# Usage:
#   KUBECONFIG=./kubeconfig ./scripts/sync-tbot-identity.sh
#
# Cron / systemd timer: runs every 30 minutes to keep identity fresh
# See: scripts/install-tbot-sync-timer.sh

set -euo pipefail

KUBECONFIG="${KUBECONFIG:-$(pwd)/kubeconfig}"
IDENTITY_DIR="${HOME}/.local/share/tbot/identity"
IDENTITY_FILE="${IDENTITY_DIR}/identity"

export KUBECONFIG

mkdir -p "$IDENTITY_DIR"

echo "==> Syncing tbot identity from k8s Secret..."
kubectl get secret tbot-identity -n teleport \
  -o jsonpath='{.data.identity}' | base64 -d > "$IDENTITY_FILE"

chmod 600 "$IDENTITY_FILE"

echo "==> Verifying identity..."
tsh ls --proxy=teleport.starstalk.io -i "$IDENTITY_FILE" 2>&1 | head -5

echo "==> Identity synced to $IDENTITY_FILE"
