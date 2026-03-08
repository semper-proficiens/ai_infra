#!/usr/bin/env bash
# seed-starstalk-env.sh — create /etc/starstalk/starstalk.env on the runner node
#
# Runs ON the remote node (sent via run-on-node.sh).
# Expects VAULT_ROLE_ID and VAULT_SECRET_ID injected as env vars.
#
set -euo pipefail

: "${VAULT_ROLE_ID:?VAULT_ROLE_ID must be set}"
: "${VAULT_SECRET_ID:?VAULT_SECRET_ID must be set}"

ENV_DIR="/etc/starstalk"
ENV_FILE="${ENV_DIR}/starstalk.env"

echo "==> Creating ${ENV_FILE}..."

mkdir -p "${ENV_DIR}"
cat > "${ENV_FILE}" <<EOF
VAULT_ROLE_ID=${VAULT_ROLE_ID}
VAULT_SECRET_ID=${VAULT_SECRET_ID}
EOF
chmod 600 "${ENV_FILE}"
chown root:root "${ENV_FILE}"

echo "==> Reloading and restarting starstalk.service..."
systemctl daemon-reload
systemctl enable starstalk
systemctl restart starstalk

# Give it a moment to start
sleep 3

if systemctl is-active --quiet starstalk; then
  echo "==> starstalk.service is running."
else
  echo "==> starstalk.service failed to start. Recent logs:" >&2
  journalctl -u starstalk -n 30 --no-pager >&2
  exit 1
fi
