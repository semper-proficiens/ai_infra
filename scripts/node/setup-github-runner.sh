#!/usr/bin/env bash
# setup-github-runner.sh — install and register GitHub Actions runner on a node
#
# Runs ON the remote node (sent via run-on-node.sh).
# Expects REG_TOKEN and GITHUB_REPO injected as env vars.
#
# Idempotent: skips configuration if runner service is already active.
#
set -euo pipefail

: "${REG_TOKEN:?REG_TOKEN must be set}"
: "${GITHUB_REPO:?GITHUB_REPO must be set}"

RUNNER_VERSION="2.322.0"
RUNNER_DIR="/opt/actions-runner"
RUNNER_USER="github-runner"
RUNNER_LABELS="self-hosted,proxmox,linux"
RUNNER_NAME="proxmox-starstalk-runner"

# Check if already registered and running
if systemctl list-units --type=service --state=active | grep -q "actions.runner"; then
  echo "==> GitHub Actions runner service already active. Skipping registration."
  exit 0
fi

echo "==> Installing dependencies..."
apt-get update -qq
apt-get install -y --no-install-recommends libicu-dev libkrb5-dev zlib1g >/dev/null

# Create runner system user if not present
if ! id "${RUNNER_USER}" &>/dev/null; then
  useradd -r -m -s /bin/bash "${RUNNER_USER}"
fi

# Download runner tarball if not already present
mkdir -p "${RUNNER_DIR}"
if [[ ! -f "${RUNNER_DIR}/run.sh" ]]; then
  ARCH="linux-x64"
  TARBALL="actions-runner-${ARCH}-${RUNNER_VERSION}.tar.gz"
  URL="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${TARBALL}"
  echo "==> Downloading GitHub Actions runner v${RUNNER_VERSION}..."
  curl -sSfL "${URL}" | tar -xz -C "${RUNNER_DIR}"
fi

chown -R "${RUNNER_USER}:${RUNNER_USER}" "${RUNNER_DIR}"

# Configure runner
echo "==> Configuring runner (repo=${GITHUB_REPO})..."
cd "${RUNNER_DIR}"
sudo -u "${RUNNER_USER}" ./config.sh \
  --url "https://github.com/${GITHUB_REPO}" \
  --token "${REG_TOKEN}" \
  --name "${RUNNER_NAME}" \
  --labels "${RUNNER_LABELS}" \
  --runnergroup "Default" \
  --unattended \
  --replace

# Install and start systemd service
echo "==> Installing runner service..."
./svc.sh install "${RUNNER_USER}"
./svc.sh start

echo "==> GitHub Actions runner installed and started."
systemctl status "$(./svc.sh status 2>/dev/null | grep -oP 'actions\.runner\S+\.service' | head -1)" --no-pager || true
