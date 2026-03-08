#!/usr/bin/env bash
# seed-runner-env.sh — create /etc/starstalk/starstalk.env on the runner LXC
#
# Reads VAULT_ROLE_ID and VAULT_SECRET_ID from .deploy-creds (gitignored),
# then ships scripts/node/seed-starstalk-env.sh to the runner via tsh.
#
# Usage:
#   ./scripts/seed-runner-env.sh
#   VAULT_ROLE_ID=<id> VAULT_SECRET_ID=<secret> ./scripts/seed-runner-env.sh
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Load deploy creds if file exists
if [[ -f "${REPO_ROOT}/.deploy-creds" ]]; then
  # shellcheck source=/dev/null
  source "${REPO_ROOT}/.deploy-creds"
fi

: "${VAULT_ROLE_ID:?VAULT_ROLE_ID must be set (in .deploy-creds or env)}"
: "${VAULT_SECRET_ID:?VAULT_SECRET_ID must be set (in .deploy-creds or env)}"

TARGET_NODE="${TARGET_NODE:-starstalk-runner}"

echo "==> Seeding starstalk.env on ${TARGET_NODE}..."

"${REPO_ROOT}/scripts/run-on-node.sh" \
  "${TARGET_NODE}" \
  "${REPO_ROOT}/scripts/node/seed-starstalk-env.sh" \
  "VAULT_ROLE_ID=${VAULT_ROLE_ID}" \
  "VAULT_SECRET_ID=${VAULT_SECRET_ID}"

echo "==> Done."
