#!/usr/bin/env bash
# agents/ollama/setup.sh — install and configure Ollama for agent use
# Run on the WSL2 machine that has the GPU (RTX 3060 12GB).
# No secrets required. Pulls models listed in MODELS env var.
set -euo pipefail

MODELS="${MODELS:-qwen2.5-coder:14b-instruct-q4_K_M qwen2.5:7b}"

echo "==> Installing Ollama..."
if ! command -v ollama &>/dev/null; then
  curl -fsSL https://ollama.com/install.sh | sh
else
  echo "    Ollama already installed: $(ollama --version)"
fi

echo "==> Installing systemd service..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp "$SCRIPT_DIR/ollama.service" /etc/systemd/system/ollama.service
systemctl daemon-reload
systemctl enable ollama
systemctl restart ollama

echo "==> Waiting for Ollama to start..."
for i in $(seq 1 15); do
  if curl -sf http://localhost:11434/api/tags &>/dev/null; then
    echo "    Ollama is up."
    break
  fi
  sleep 2
done

echo "==> Pulling models..."
for model in $MODELS; do
  echo "    Pulling $model..."
  ollama pull "$model"
done

echo "==> Done. Ollama is running at http://localhost:11434"
echo "    Models available:"
ollama list
