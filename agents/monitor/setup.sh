#!/usr/bin/env bash
# agents/monitor/setup.sh — build and install the monitor agent daemon.
# Requires: Go 1.23+, nvidia-smi (for GPU checks), tsh (for k3s access).
set -euo pipefail

REPO_PATH="${REPO_PATH:-/home/erniepy/gh_repos/starstalk}"
CONFIG_ENV="${CONFIG_ENV:-/etc/monitor-agent/config.env}"
BINARY_DEST="${BINARY_DEST:-/usr/local/bin/monitor-agent}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITOR_SRC="${MONITOR_SRC:-$REPO_PATH/tools/monitor}"

echo "==> Building monitor-agent binary..."
if [ ! -d "$MONITOR_SRC" ]; then
  echo "    ERROR: monitor source not found at $MONITOR_SRC"
  echo "    Set MONITOR_SRC= to the correct path."
  exit 1
fi
cd "$MONITOR_SRC"
go build -o /tmp/monitor-agent .
sudo install -m 755 /tmp/monitor-agent "$BINARY_DEST"
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
sudo cp "$SCRIPT_DIR/monitor.service" /etc/systemd/system/monitor-agent.service
sudo systemctl daemon-reload

echo ""
echo "==> Done. Next steps:"
echo "    1. Edit $CONFIG_ENV (fill in PROXMOX_TOKEN, CONFIG_WORKER_TOKEN, etc.)"
echo "    2. sudo systemctl enable --now monitor-agent"
echo "    3. sudo journalctl -fu monitor-agent"
