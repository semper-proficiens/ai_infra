#!/usr/bin/env bash
# setup-adguard.sh — Deploy AdGuard Home on LXC 109 (ai-knowledge-storage, 192.168.0.96)
#
# Idempotent: safe to re-run. Skips steps already done.
# Requires: tsh certs valid (make renew-teleport-bot if expired)
#
# After running, set DNS on:
#   - Proxmox VMs: /etc/resolv.conf → nameserver 192.168.0.96
#   - k3s nodes:   same (via cloud-init or manual)
#   - WSL2:        /etc/wsl.conf [network] generateResolvConf=false
#                  /etc/resolv.conf → nameserver 192.168.0.96
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NODE="ai-knowledge-storage"
TSH="tsh ssh --proxy=teleport.starstalk.io -i ${HOME}/.local/share/tbot/identity/identity"

echo "==> Deploying AdGuard Home on ${NODE}..."

# ── 1. Create dirs + write docker-compose ────────────────────────────────────
$TSH root@${NODE} bash -s << 'REMOTE'
set -euo pipefail
mkdir -p /opt/adguard/work /opt/adguard/conf

systemctl is-active --quiet apache2 2>/dev/null && \
  echo "Note: apache2 on port 80, AdGuard uses 3000 for UI (no conflict)" || true

cat > /opt/adguard/docker-compose.yaml << 'COMPOSE'
services:
  adguard:
    image: adguard/adguardhome:latest
    container_name: adguardhome
    restart: unless-stopped
    network_mode: host
    volumes:
      - /opt/adguard/work:/opt/adguardhome/work
      - /opt/adguard/conf:/opt/adguardhome/conf
COMPOSE
echo "docker-compose.yaml written"
REMOTE

# ── 2. Copy config (always overwrite so rewrites stay current) ────────────────
echo "==> Uploading AdGuardHome.yaml..."
$TSH root@${NODE} "cat > /opt/adguard/conf/AdGuardHome.yaml" < "${SCRIPT_DIR}/AdGuardHome.yaml"

# ── 3. Install docker if missing, then start ─────────────────────────────────
$TSH root@${NODE} bash -s << 'REMOTE'
set -euo pipefail

if ! command -v docker &>/dev/null; then
  echo "Installing Docker..."
  curl -fsSL https://get.docker.com | sh
fi

cd /opt/adguard
docker compose pull --quiet
docker compose up -d

echo "Waiting for AdGuard to start..."
sleep 5

if docker compose ps | grep -q "running\|Up"; then
  echo "AdGuard Home is running"
  echo "  Web UI: http://192.168.0.96:3000"
  echo "  DNS:    192.168.0.96:53"
else
  echo "ERROR: AdGuard container failed to start"
  docker compose logs --tail=20
  exit 1
fi
REMOTE

echo ""
echo "==> AdGuard Home deployed."
echo ""
echo "Next steps:"
echo "  1. Open http://192.168.0.96:3000 and complete setup wizard (set admin password)"
echo "  2. Update k3s nodes DNS: make update-node-dns"
echo "  3. Update WSL2 DNS:     echo 'nameserver 192.168.0.96' | sudo tee /etc/resolv.conf"
