#!/usr/bin/env bash
# update-node-dns.sh — Point k3s nodes at AdGuard Home for DNS
#
# Updates /etc/resolv.conf on all k3s nodes to use AdGuard Home
# (192.168.0.96) as the primary DNS resolver.
# Uses direct SSH (bootstrap access) since these nodes are not in Teleport.
set -euo pipefail

SSH_KEY="${SSH_KEY:-${HOME}/.ssh/github_wsl}"
SSH_USER="ubuntu"
ADGUARD_IP="192.168.0.96"

K3S_NODES=(
  "192.168.0.80"   # k3s-control
  "192.168.0.81"   # k3s-worker-0
  "192.168.0.82"   # k3s-worker-1
)

for NODE_IP in "${K3S_NODES[@]}"; do
  echo "==> Updating DNS on ${NODE_IP}..."
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "${SSH_KEY}" \
    "${SSH_USER}@${NODE_IP}" bash -s << REMOTE
# Disable systemd-resolved managed resolv.conf
if systemctl is-active --quiet systemd-resolved; then
  systemctl disable --now systemd-resolved 2>/dev/null || true
fi

# Write static resolv.conf
cat > /etc/resolv.conf << 'RESOLVCONF'
nameserver ${ADGUARD_IP}
nameserver 1.1.1.1
search starstalk.internal svc.cluster.local
RESOLVCONF

echo "  DNS updated on ${NODE_IP}"
REMOTE
done

echo ""
echo "==> All k3s nodes now resolve via AdGuard Home (${ADGUARD_IP})"
echo "    Test: dig vault.starstalk.internal @${ADGUARD_IP}"
