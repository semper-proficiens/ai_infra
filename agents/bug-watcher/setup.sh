#!/usr/bin/env bash
# agents/bug-watcher/setup.sh — build and install the bug-watcher daemon.
# Requires: Go 1.23+, git, gh CLI (for PR creation), Ollama running.
set -euo pipefail

REPO_PATH="${REPO_PATH:-/home/erniepy/gh_repos/starstalk}"
CONFIG_ENV="${CONFIG_ENV:-/etc/bug-watcher/config.env}"
BINARY_DEST="${BINARY_DEST:-/usr/local/bin/bug-fix-agent}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Building bug-fix-agent binary..."
cd "$REPO_PATH/tools/bug-fix-agent"
go build -o /tmp/bug-fix-agent .
sudo install -m 755 /tmp/bug-fix-agent "$BINARY_DEST"
echo "    Installed: $BINARY_DEST"

echo "==> Installing config..."
if [ ! -f "$CONFIG_ENV" ]; then
  sudo mkdir -p "$(dirname "$CONFIG_ENV")"
  sudo cp "$SCRIPT_DIR/config.env.template" "$CONFIG_ENV"
  echo "    Config template copied to $CONFIG_ENV"
  echo "    !! Fill in the values before starting the service !!"
else
  echo "    Config already exists at $CONFIG_ENV — not overwriting."
fi

echo "==> Installing systemd service..."
sudo cp "$SCRIPT_DIR/bug-watcher.service" /etc/systemd/system/bug-watcher.service
sudo systemctl daemon-reload

echo "==> Creating state directory..."
sudo mkdir -p /var/lib/bug-watcher
sudo chown "$USER:$USER" /var/lib/bug-watcher

echo ""
echo "==> Done. Next steps:"
echo "    1. Edit $CONFIG_ENV (fill in GITHUB_TOKEN, GITHUB_REPO, CONFIG_WORKER_TOKEN)"
echo "    2. sudo systemctl enable --now bug-watcher"
echo "    3. sudo journalctl -fu bug-watcher"
