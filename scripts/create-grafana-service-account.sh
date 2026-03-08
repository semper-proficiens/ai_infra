#!/usr/bin/env bash
# create-grafana-service-account.sh — create Grafana automation service account
#
# Creates a Grafana service account with Admin role and stores the token
# as a Kubernetes Secret (grafana-automation-token in monitoring namespace).
#
# Usage:
#   KUBECONFIG=./kubeconfig ./scripts/create-grafana-service-account.sh
#
# The token is stored in:
#   k8s Secret: grafana-automation-token (monitoring ns) — key: token
#
# Re-running is idempotent: deletes and recreates the token if the SA exists.

set -euo pipefail

KUBECONFIG="${KUBECONFIG:-$(pwd)/kubeconfig}"
NAMESPACE="monitoring"
SVC_NAME="kube-prometheus-stack-grafana"
SA_NAME="automation"
LOCAL_PORT="13001"

export KUBECONFIG

# ── 1. Get admin password from k8s secret ────────────────────────────────────
echo "==> Reading Grafana admin password from k8s secret..."
GRAFANA_PASS=$(kubectl get secret -n "$NAMESPACE" kube-prometheus-stack-grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d)

if [[ -z "$GRAFANA_PASS" ]]; then
  echo "ERROR: Could not read Grafana admin password from secret"
  exit 1
fi

# ── 2. Port-forward Grafana ───────────────────────────────────────────────────
echo "==> Starting port-forward to Grafana..."
kubectl port-forward "svc/$SVC_NAME" "${LOCAL_PORT}:80" -n "$NAMESPACE" &>/dev/null &
PF_PID=$!
trap "kill $PF_PID 2>/dev/null; wait $PF_PID 2>/dev/null" EXIT

sleep 3
GRAFANA_URL="http://localhost:${LOCAL_PORT}"

# ── 3. Create or find service account ────────────────────────────────────────
echo "==> Creating service account '${SA_NAME}'..."
SA_RESP=$(curl -s -X POST "${GRAFANA_URL}/api/serviceaccounts" \
  -H "Content-Type: application/json" \
  -u "admin:${GRAFANA_PASS}" \
  -d "{\"name\":\"${SA_NAME}\",\"role\":\"Admin\",\"isDisabled\":false}")

SA_ID=$(echo "$SA_RESP" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d["id"])' 2>/dev/null || true)

if [[ -z "$SA_ID" ]]; then
  # SA already exists — find it
  echo "==> Service account may exist, searching..."
  SA_ID=$(curl -s "${GRAFANA_URL}/api/serviceaccounts/search?query=${SA_NAME}" \
    -u "admin:${GRAFANA_PASS}" | python3 -c \
    'import sys,json; d=json.load(sys.stdin); print(d["serviceAccounts"][0]["id"])' 2>/dev/null)
fi

if [[ -z "$SA_ID" ]]; then
  echo "ERROR: Could not create or find service account"
  exit 1
fi
echo "==> Service account ID: $SA_ID"

# ── 4. Delete existing tokens (idempotent) ────────────────────────────────────
echo "==> Removing existing tokens..."
EXISTING=$(curl -s "${GRAFANA_URL}/api/serviceaccounts/${SA_ID}/tokens" \
  -u "admin:${GRAFANA_PASS}" | python3 -c \
  'import sys,json; [print(t["id"]) for t in json.load(sys.stdin)]' 2>/dev/null || true)

for TID in $EXISTING; do
  curl -s -X DELETE "${GRAFANA_URL}/api/serviceaccounts/${SA_ID}/tokens/${TID}" \
    -u "admin:${GRAFANA_PASS}" &>/dev/null || true
done

# ── 5. Create new token ───────────────────────────────────────────────────────
echo "==> Creating new service account token..."
TOKEN_RESP=$(curl -s -X POST "${GRAFANA_URL}/api/serviceaccounts/${SA_ID}/tokens" \
  -H "Content-Type: application/json" \
  -u "admin:${GRAFANA_PASS}" \
  -d '{"name":"automation-token","secondsToLive":0}')

TOKEN=$(echo "$TOKEN_RESP" | python3 -c 'import sys,json; print(json.load(sys.stdin)["key"])')

if [[ -z "$TOKEN" ]]; then
  echo "ERROR: Failed to create token: $TOKEN_RESP"
  exit 1
fi

# ── 6. Store as k8s secret ───────────────────────────────────────────────────
echo "==> Storing token as k8s secret grafana-automation-token..."
kubectl create secret generic grafana-automation-token \
  --from-literal=token="$TOKEN" \
  --namespace "$NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Service account 'automation' created (Admin role)."
echo "Token stored in: Secret/grafana-automation-token (monitoring)"
echo ""
echo "To retrieve the token:"
echo "  kubectl get secret grafana-automation-token -n monitoring \\"
echo "    -o jsonpath='{.data.token}' | base64 -d"
echo ""
echo "API usage:"
echo "  curl -H 'Authorization: Bearer <token>' https://grafana.starstalk.io/api/dashboards/home"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
