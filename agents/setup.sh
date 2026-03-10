#!/usr/bin/env bash
# agents/setup.sh — master setup for all local AI agents.
# Run once on a fresh machine to install everything in order.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================"
echo " StarsTalk Agent Setup"
echo "========================================"
echo ""

run_setup() {
  local name="$1"
  local script="$SCRIPT_DIR/$name/setup.sh"
  echo "----------------------------------------"
  echo " Setting up: $name"
  echo "----------------------------------------"
  bash "$script"
  echo ""
}

# 1. Ollama (GPU inference server) — must be first.
run_setup "ollama"

# 2. Bug-watcher daemon.
run_setup "bug-watcher"

# 3. Monitor agent.
run_setup "monitor"

echo "========================================"
echo " All agents installed."
echo ""
echo " Remaining manual steps:"
echo "   - Fill in /etc/bug-watcher/config.env (GITHUB_TOKEN etc.)"
echo "   - Fill in /etc/monitor-agent/config.env (PROXMOX_TOKEN etc.)"
echo "   - sudo systemctl enable --now bug-watcher"
echo "   - sudo systemctl enable --now monitor-agent"
echo "========================================"
