#!/usr/bin/env bash
# setup-runner.sh — register GitHub Actions runner on starstalk-runner
#
# Fetches a one-time registration token from GitHub, then ships
# scripts/node/setup-github-runner.sh to the runner via tsh.
#
# Usage:
#   ./scripts/setup-runner.sh
#
# Requires:
#   .github-creds with GITHUB_TOKEN (fine-grained PAT, Actions:write on the repo)
#   GITHUB_REPO env var or default below
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -f "${REPO_ROOT}/.github-creds" ]]; then
  # shellcheck source=/dev/null
  source "${REPO_ROOT}/.github-creds"
fi

: "${GITHUB_TOKEN:?GITHUB_TOKEN must be set (in .github-creds or env)}"
GITHUB_REPO="${GITHUB_REPO:-semper-proficiens/starstalk}"
TARGET_NODE="${TARGET_NODE:-starstalk-runner}"

echo "==> Fetching runner registration token for ${GITHUB_REPO}..."

REG_TOKEN=$(curl -sSf -X POST \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/repos/${GITHUB_REPO}/actions/runners/registration-token" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")

echo "==> Sending setup script to ${TARGET_NODE}..."

"${REPO_ROOT}/scripts/run-on-node.sh" \
  "${TARGET_NODE}" \
  "${REPO_ROOT}/scripts/node/setup-github-runner.sh" \
  "REG_TOKEN=${REG_TOKEN}" \
  "GITHUB_REPO=${GITHUB_REPO}"

echo "==> Runner setup complete."
