#!/usr/bin/env bash
# renew-teleport-bot.sh — re-join tbot after cert expiry
#
# Usage:
#   TOKEN=<new-join-token> ./scripts/renew-teleport-bot.sh
#
# Or interactively (prompts for token):
#   ./scripts/renew-teleport-bot.sh
#
# When to run:
#   - After cert expiry (tsh returns "cert has expired")
#   - After tbot daemon is recreated
#   - After "make renew-teleport-bot TOKEN=<token>" from the Makefile
#
# After running this, tbot will re-join and write fresh certs to:
#   ~/.local/share/tbot/identity/identity
# All make targets (ssh, logs, status, etc.) will work again.

set -euo pipefail

TBOT_CONFIG="${HOME}/.config/tbot.yaml"
TBOT_TOKEN_FILE="${HOME}/.config/.teleport-bot-token"
PROXY="teleport.starstalk.io:443"

# ── 1. Get token ──────────────────────────────────────────────────────────────
if [[ -n "${TOKEN:-}" ]]; then
  NEW_TOKEN="$TOKEN"
elif [[ -f "$TBOT_TOKEN_FILE" ]]; then
  echo "==> Reading stored token from $TBOT_TOKEN_FILE"
  NEW_TOKEN="$(cat "$TBOT_TOKEN_FILE")"
else
  echo "==> No TOKEN env var and no stored token at $TBOT_TOKEN_FILE"
  echo "    Run: tctl bots add claude-bot-wsl2 --roles=bot-node-access --token-ttl 0"
  echo "    Then: TOKEN=<token> ./scripts/renew-teleport-bot.sh"
  exit 1
fi

echo "==> Stopping tbot daemon..."
systemctl --user stop tbot 2>/dev/null || true
sleep 2

# ── 2. Wipe expired identity (stale certs block re-join) ─────────────────────
echo "==> Clearing expired identity state..."
rm -rf "${HOME}/.local/share/tbot/identity"
mkdir -p "${HOME}/.local/share/tbot/identity"

# ── 3. Inject token into tbot config ─────────────────────────────────────────
echo "==> Updating tbot config with new join token..."
cat > "$TBOT_CONFIG" <<EOF
version: v2
proxy_server: ${PROXY}

onboarding:
  join_method: token
  token: "${NEW_TOKEN}"

storage:
  type: directory
  path: ${HOME}/.local/share/tbot

outputs:
  - type: identity
    destination:
      type: directory
      path: ${HOME}/.local/share/tbot/identity
EOF

# Store token for future renewals (multi-use tokens only)
echo "$NEW_TOKEN" > "$TBOT_TOKEN_FILE"
chmod 600 "$TBOT_TOKEN_FILE"
echo "==> Token saved to $TBOT_TOKEN_FILE for future renewals"

# ── 4. Re-join (one-shot to write initial certs) ─────────────────────────────
echo "==> Running tbot --oneshot to issue fresh certs..."
tbot start --config "$TBOT_CONFIG" --oneshot

echo "==> Verifying identity..."
tsh --proxy="${PROXY}" -i "${HOME}/.local/share/tbot/identity/identity" ls 2>&1 | head -3

# ── 5. Restart daemon ─────────────────────────────────────────────────────────
echo "==> Starting tbot daemon..."
systemctl --user start tbot

echo ""
echo "✅ tbot renewed. Run 'make status' to verify node access."
