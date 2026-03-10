#!/usr/bin/env bash
# setup-vault-pki.sh — Enable Vault PKI engine and create internal CA
#
# Idempotent: safe to re-run. Checks if PKI is already enabled.
# Requires: valid Teleport certs (make renew-teleport-bot if expired)
#
# After running:
#   1. Update k8s/cert-manager/issuer-vault-pki.yaml caBundle field
#   2. Create vault-pki-approle secret in cert-manager namespace
#   3. Apply issuer-vault-pki.yaml
#   4. Enable Vault TLS listener (see comments at bottom)
set -euo pipefail

TSH="tsh ssh --proxy=teleport.starstalk.io -i ${HOME}/.local/share/tbot/identity/identity"
VAULT_NODE="starstalk-hc-vault"
VAULT_ADDR="http://127.0.0.1:8200"

echo "==> Setting up Vault PKI on ${VAULT_NODE}..."

$TSH root@${VAULT_NODE} bash -s << 'REMOTE'
set -euo pipefail
export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="$(cat /root/.vault-token)"

# ── Root PKI engine ─────────────────────────────────────────────────────────
if vault secrets list | grep -q "^pki/"; then
  echo "PKI engine already enabled at pki/ — skipping"
else
  echo "Enabling PKI secrets engine..."
  vault secrets enable -path=pki pki
  vault secrets tune -max-lease-ttl=87600h pki
fi

# ── Root CA ──────────────────────────────────────────────────────────────────
CA_EXISTS=$(vault read -format=json pki/cert/ca 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('certificate','')[:10])" 2>/dev/null || true)
if [[ -n "${CA_EXISTS}" ]]; then
  echo "Root CA already exists — skipping generation"
else
  echo "Generating root CA..."
  vault write -format=json pki/root/generate/internal \
    common_name="Starstalk Internal CA" \
    ttl="87600h" \
    key_type="rsa" \
    key_bits="4096" \
    | python3 -c "
import sys, json
d = json.load(sys.stdin)
cert = d['data']['certificate']
print(cert)
" > /tmp/starstalk-ca.crt
  echo "Root CA written to /tmp/starstalk-ca.crt"
fi

# Export CA cert regardless
vault read -format=json pki/cert/ca | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d['data']['certificate'])
" > /tmp/starstalk-ca.crt

# ── CRL / issuing URLs ────────────────────────────────────────────────────────
vault write pki/config/urls \
  issuing_certificates="https://vault.starstalk.internal:8200/v1/pki/ca" \
  crl_distribution_points="https://vault.starstalk.internal:8200/v1/pki/crl"

# ── Role for internal services ────────────────────────────────────────────────
echo "Creating/updating internal-services role..."
vault write pki/roles/internal-services \
  allowed_domains="starstalk.internal,svc.cluster.local,starstalk.io" \
  allow_subdomains=true \
  allow_bare_domains=false \
  allow_glob_domains=false \
  max_ttl="720h" \
  ttl="168h" \
  key_type="rsa" \
  key_bits="2048"

# ── Policy for cert-manager ───────────────────────────────────────────────────
echo "Creating cert-manager policy..."
vault policy write cert-manager - << 'POLICY'
path "pki/sign/internal-services" {
  capabilities = ["create", "update"]
}
path "pki/issue/internal-services" {
  capabilities = ["create", "update"]
}
POLICY

# ── AppRole for cert-manager ──────────────────────────────────────────────────
vault auth enable approle 2>/dev/null || true   # already enabled is fine

vault write auth/approle/role/cert-manager \
  policies=cert-manager \
  token_ttl=1h \
  token_max_ttl=4h \
  secret_id_ttl=0   # non-expiring secret_id

ROLE_ID=$(vault read -format=json auth/approle/role/cert-manager/role-id | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['role_id'])")
SECRET_ID=$(vault write -format=json -f auth/approle/role/cert-manager/secret-id | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['secret_id'])")

echo ""
echo "══════════════════════════════════════════════════════════"
echo "Vault PKI setup complete!"
echo ""
echo "CA cert: /tmp/starstalk-ca.crt"
echo ""
echo "cert-manager AppRole credentials (add to k8s secret):"
echo "  VAULT_CERTMANAGER_ROLE_ID=${ROLE_ID}"
echo "  VAULT_CERTMANAGER_SECRET_ID=[redacted — see above output only]"
echo ""
echo "Next steps:"
echo "  1. Copy CA cert to all nodes: make distribute-ca-cert"
echo "  2. Create k8s secret: kubectl create secret generic vault-pki-approle \\"
echo "       --from-literal=roleId=\${ROLE_ID} --from-literal=secretId=\${SECRET_ID} \\"
echo "       --namespace cert-manager"
echo "  3. Update issuer-vault-pki.yaml caBundle with base64 CA cert"
echo "  4. Enable Vault TLS (see README in k8s/cert-manager/)"
echo "══════════════════════════════════════════════════════════"
REMOTE
