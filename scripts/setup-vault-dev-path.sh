#!/usr/bin/env bash
# setup-vault-dev-path.sh — create Vault dev AppRole + dev KV path
#
# Run ONCE on the Vault VM (192.168.0.74) as root:
#   bash /tmp/setup-vault-dev-path.sh
#
# Copy to Vault VM first:
#   scp scripts/setup-vault-dev-path.sh root@<vault-vm>:/tmp/
#
# What it does:
#   1. Copies all keys from secret/starstalk → secret/starstalk-dev
#   2. Overrides ENVIRONMENT=dev, PORT=8080, DB_HOST=dev in the dev path
#   3. Creates a dedicated 'starstalk-dev' policy (reads secret/starstalk-dev only)
#   4. Creates a 'starstalk-dev' AppRole using that policy
#   5. Prints the role_id and secret_id to store in k8s secret 'starstalk-vault-dev'
#
# Result: dev pods use starstalk-dev AppRole → can only read secret/starstalk-dev
#         prod pods use starstalk AppRole → reads secret/starstalk

set -euo pipefail

export VAULT_ADDR="http://localhost:8200"

if [[ -f /root/.vault-token ]]; then
  export VAULT_TOKEN
  VAULT_TOKEN=$(cat /root/.vault-token)
else
  echo "ERROR: /root/.vault-token not found. Run as root on the Vault VM."
  exit 1
fi

echo "==> Vault connected: $(vault version)"

# ── 1. Copy prod data → dev path with overrides ───────────────────────────────
echo ""
echo "==> Reading prod config from secret/starstalk..."
vault kv get -format=json secret/starstalk | python3 -c "
import sys, json, subprocess, shlex

d = json.load(sys.stdin)
data = d['data']['data']

# Override env-specific keys for dev
data['ENVIRONMENT'] = 'dev'
data['PORT'] = '8080'
data['DB_HOST'] = 'starstalk-pg-dev-rw.starstalk-dev.svc.cluster.local'
data['DB_PORT'] = '5432'

# Write to secret/starstalk-dev using vault CLI
cmd = ['vault', 'kv', 'put', 'secret/starstalk-dev']
for k, v in data.items():
    cmd.append(f'{k}={v}')

print('Writing', len(data), 'keys to secret/starstalk-dev...')
result = subprocess.run(cmd, capture_output=True, text=True)
if result.returncode != 0:
    print('ERROR:', result.stderr)
    sys.exit(1)
print(result.stdout)
"

echo "==> Verifying dev path overrides..."
echo "  ENVIRONMENT=$(vault kv get -field=ENVIRONMENT secret/starstalk-dev)"
echo "  PORT=$(vault kv get -field=PORT secret/starstalk-dev)"
echo "  DB_HOST=$(vault kv get -field=DB_HOST secret/starstalk-dev)"

# ── 2. Create dev-specific Vault policy ──────────────────────────────────────
echo ""
echo "==> Creating vault policy: starstalk-dev-policy..."
vault policy write starstalk-dev-policy - <<'POLICY'
# Dev AppRole: can ONLY read the dev secret path
path "secret/data/starstalk-dev" {
  capabilities = ["read"]
}
path "secret/metadata/starstalk-dev" {
  capabilities = ["read", "list"]
}
POLICY

# ── 3. Create dev AppRole ─────────────────────────────────────────────────────
echo ""
echo "==> Creating AppRole: starstalk-dev..."
vault auth enable approle 2>/dev/null || true  # already enabled

vault write auth/approle/role/starstalk-dev \
  policies="starstalk-dev-policy" \
  token_ttl=1h \
  token_max_ttl=4h \
  secret_id_ttl=0   # non-expiring secret ID

# ── 4. Get credentials ────────────────────────────────────────────────────────
echo ""
echo "==> Retrieving dev AppRole credentials..."
ROLE_ID=$(vault read -field=role_id auth/approle/role/starstalk-dev/role-id)
SECRET_ID=$(vault write -force -field=secret_id auth/approle/role/starstalk-dev/secret-id)

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Dev AppRole created. Run this on your WSL2 machine:"
echo ""
echo "  kubectl create secret generic starstalk-vault-dev \\"
echo "    --from-literal=VAULT_ROLE_ID='${ROLE_ID}' \\"
echo "    --from-literal=VAULT_SECRET_ID='${SECRET_ID}' \\"
echo "    --namespace starstalk-dev \\"
echo "    --dry-run=client -o yaml | kubectl apply -f -"
echo ""
echo "  Then run: make deploy-dev  # or push to dev branch"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
