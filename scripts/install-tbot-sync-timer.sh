#!/usr/bin/env bash
# install-tbot-sync-timer.sh — install systemd user timer to keep WSL2 tbot identity fresh
#
# Runs sync-tbot-identity.sh every 30 minutes so the local identity file
# never expires. The k8s tbot pod renews certs every hour; this syncs within 30m.
#
# Run once after tbot k8s deployment is up:
#   KUBECONFIG=./kubeconfig ./scripts/install-tbot-sync-timer.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SYSTEMD_DIR="${HOME}/.config/systemd/user"

mkdir -p "$SYSTEMD_DIR"

# ── Service unit ──────────────────────────────────────────────────────────────
cat > "${SYSTEMD_DIR}/tbot-sync.service" <<EOF
[Unit]
Description=Sync tbot identity from k8s to WSL2
After=network-online.target

[Service]
Type=oneshot
Environment=KUBECONFIG=${REPO_ROOT}/kubeconfig
ExecStart=${REPO_ROOT}/scripts/sync-tbot-identity.sh
StandardOutput=journal
StandardError=journal
EOF

# ── Timer unit ────────────────────────────────────────────────────────────────
cat > "${SYSTEMD_DIR}/tbot-sync.timer" <<EOF
[Unit]
Description=Keep tbot identity fresh (sync every 30 min)

[Timer]
OnBootSec=2min
OnUnitActiveSec=30min
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now tbot-sync.timer

echo "==> tbot-sync timer installed and started"
echo "    Next run: $(systemctl --user show tbot-sync.timer -p NextElapseUSecRealtime --value | \
  python3 -c 'import sys,datetime; print(datetime.datetime.fromtimestamp(int(sys.stdin.read().strip())//1000000))'  2>/dev/null || echo 'within 30 min')"
echo ""
echo "Status: systemctl --user status tbot-sync.timer"
echo "Logs:   journalctl --user -u tbot-sync.service"
