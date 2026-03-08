#!/usr/bin/env bash
# run-on-node.sh — run a local script on a remote node via tsh ssh
#
# Usage:
#   ./scripts/run-on-node.sh <node> <local-script> [VAR=value ...]
#
# Examples:
#   ./scripts/run-on-node.sh starstalk-runner scripts/node/seed-starstalk-env.sh
#   ./scripts/run-on-node.sh starstalk-runner scripts/node/setup-github-runner.sh REG_TOKEN=abc GITHUB_REPO=org/repo
#
# Environment:
#   TSH_PROXY     Teleport proxy address (default: teleport.starstalk.io)
#   TSH_IDENTITY  Path to tbot identity file (default: ~/.local/share/tbot/identity/identity)
#
set -euo pipefail

NODE="${1:?Usage: run-on-node.sh <node> <script> [VAR=value ...]}"
SCRIPT="${2:?Usage: run-on-node.sh <node> <script> [VAR=value ...]}"
shift 2

TSH_PROXY="${TSH_PROXY:-teleport.starstalk.io}"
TSH_IDENTITY="${TSH_IDENTITY:-${HOME}/.local/share/tbot/identity/identity}"

if [[ ! -f "${SCRIPT}" ]]; then
  echo "Error: script not found: ${SCRIPT}" >&2
  exit 1
fi

if [[ ! -f "${TSH_IDENTITY}" ]]; then
  echo "Error: tbot identity not found at ${TSH_IDENTITY}" >&2
  echo "  Is tbot running? Check: systemctl --user status tbot" >&2
  exit 1
fi

# Build export block from remaining VAR=value args
EXPORTS=""
for arg in "$@"; do
  # Validate format — must be VAR=value, no shell injection
  if [[ ! "${arg}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
    echo "Error: invalid env arg '${arg}' — must be VAR=value" >&2
    exit 1
  fi
  EXPORTS+="export $(printf '%q=%q' "${arg%%=*}" "${arg#*=}")"$'\n'
done

echo "==> Running ${SCRIPT} on ${NODE}..."

# Prepend exports to the script, pipe to remote bash
{
  if [[ -n "${EXPORTS}" ]]; then
    printf '%s\n' "${EXPORTS}"
  fi
  cat "${SCRIPT}"
} | tsh ssh --proxy="${TSH_PROXY}" -i "${TSH_IDENTITY}" "root@${NODE}" 'bash -s'
