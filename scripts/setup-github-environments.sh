#!/usr/bin/env bash
# setup-github-environments.sh — create 'dev' and 'prod' GitHub Environments
#
# dev:  no protection — auto-deploys on every push to the dev branch
# prod: requires manual approval before the deploy job runs
#
# Run once per repo. Safe to re-run (PUT is idempotent).
#
# Requires:
#   .github-creds with GITHUB_TOKEN (fine-grained PAT, Administration:write on the repo)
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -f "${REPO_ROOT}/.github-creds" ]]; then
  # shellcheck source=/dev/null
  source "${REPO_ROOT}/.github-creds"
fi

: "${GITHUB_TOKEN:?GITHUB_TOKEN must be set (in .github-creds or env)}"
GITHUB_REPO="${GITHUB_REPO:-semper-proficiens/ai_infra}"

# Get the authenticated user's ID (used as the required reviewer for prod)
echo "==> Fetching your GitHub user ID..."
USER_ID=$(curl -sSf \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/user" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
echo "    User ID: ${USER_ID}"

# ── dev environment — no protection ──────────────────────────────────────────

echo "==> Creating 'dev' environment (no protection)..."
curl -sSf -X PUT \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  -H "Content-Type: application/json" \
  "https://api.github.com/repos/${GITHUB_REPO}/environments/dev" \
  -d '{"wait_timer":0,"prevent_self_review":false,"reviewers":[],"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}' \
  > /dev/null
echo "    'dev' environment created."

# Add dev branch as the only allowed deployment source
curl -sSf -X POST \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  -H "Content-Type: application/json" \
  "https://api.github.com/repos/${GITHUB_REPO}/environments/dev/deployment-branch-policies" \
  -d '{"name":"dev","type":"branch"}' \
  > /dev/null 2>&1 || true   # ignore if already exists

# ── prod environment — requires your manual approval ─────────────────────────

echo "==> Creating 'prod' environment (requires your approval)..."
curl -sSf -X PUT \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  -H "Content-Type: application/json" \
  "https://api.github.com/repos/${GITHUB_REPO}/environments/prod" \
  -d "{\"wait_timer\":0,\"prevent_self_review\":false,\"reviewers\":[{\"type\":\"User\",\"id\":${USER_ID}}],\"deployment_branch_policy\":null}" \
  > /dev/null
echo "    'prod' environment created (you are the required reviewer)."

echo ""
echo "==> Done. Verify at:"
echo "    https://github.com/${GITHUB_REPO}/settings/environments"
