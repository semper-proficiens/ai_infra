#!/usr/bin/env bash
# install-build-tools.sh — install Go + Docker on the runner LXC
#
# Runs ON the remote node (sent via run-on-node.sh).
# LXC must have nesting=1 enabled in Proxmox (set via Terraform enable_nesting=true).
# Idempotent — skips tools that are already installed.
#
set -euo pipefail

GO_VERSION="1.23.6"
ARCH="amd64"

# ── Docker ────────────────────────────────────────────────────────────────────

if command -v docker &>/dev/null; then
  echo "==> Docker already installed: $(docker --version)"
else
  echo "==> Installing Docker..."
  apt-get update -qq
  apt-get install -y --no-install-recommends ca-certificates curl gnupg

  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${VERSION_CODENAME}") stable" \
    > /etc/apt/sources.list.d/docker.list

  apt-get update -qq
  apt-get install -y --no-install-recommends docker-ce docker-ce-cli containerd.io

  systemctl enable docker
  systemctl start docker
  echo "==> Docker installed: $(docker --version)"
fi

# ── Go ────────────────────────────────────────────────────────────────────────

INSTALLED_GO=$(go version 2>/dev/null | grep -oP 'go\K[0-9]+\.[0-9]+\.[0-9]+' || echo "")

if [[ "${INSTALLED_GO}" == "${GO_VERSION}" ]]; then
  echo "==> Go ${GO_VERSION} already installed."
else
  echo "==> Installing Go ${GO_VERSION}..."
  TARBALL="go${GO_VERSION}.linux-${ARCH}.tar.gz"
  curl -sSfL "https://go.dev/dl/${TARBALL}" -o "/tmp/${TARBALL}"
  rm -rf /usr/local/go
  tar -C /usr/local -xzf "/tmp/${TARBALL}"
  rm "/tmp/${TARBALL}"

  # Symlink so it's available system-wide (including for the runner user)
  ln -sf /usr/local/go/bin/go   /usr/local/bin/go
  ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt

  echo "==> Go installed: $(go version)"
fi

# ── Allow runner user to use Docker ──────────────────────────────────────────

RUNNER_USER="${RUNNER_USER:-github-runner}"
if id "${RUNNER_USER}" &>/dev/null; then
  usermod -aG docker "${RUNNER_USER}"
  echo "==> Added ${RUNNER_USER} to docker group."
fi

echo ""
echo "==> Build tools ready."
echo "    Docker: $(docker --version)"
echo "    Go:     $(go version)"
