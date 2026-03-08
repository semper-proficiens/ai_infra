#!/usr/bin/env bash
# setup-alert-email.sh — create k8s Secrets for Alertmanager + Grafana SMTP
#
# Reads credentials from .alert-creds (gitignored).
# Creates or updates:
#   Secret/alertmanager-config-email  (namespace: monitoring) — full Alertmanager config
#   Secret/grafana-smtp-credentials   (namespace: monitoring) — Grafana SMTP env vars
#
# Run once after initial cluster setup, and again whenever you rotate the App Password:
#   make setup-alert-email

set -euo pipefail

CREDS="${CREDS_FILE:-.alert-creds}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE="${REPO_ROOT}/k8s/monitoring/alertmanager-config.yaml.example"
KUBECONFIG="${KUBECONFIG:-${REPO_ROOT}/kubeconfig}"
export KUBECONFIG

if [[ ! -f "$CREDS" ]]; then
  echo "ERROR: $CREDS not found."
  echo "Copy .alert-creds.example → .alert-creds and fill in your email + Gmail App Password."
  exit 1
fi

# Read creds — never print them
ALERT_EMAIL=""
ALERT_SMTP_PASSWORD=""
# shellcheck source=/dev/null
source "$CREDS"

if [[ -z "$ALERT_EMAIL" || -z "$ALERT_SMTP_PASSWORD" ]]; then
  echo "ERROR: ALERT_EMAIL and ALERT_SMTP_PASSWORD must be set in $CREDS"
  exit 1
fi

echo "==> Creating Secret/alertmanager-config-email..."

# Render alertmanager config with real values (never echo the values)
RENDERED="$(sed \
  -e "s|<YOUR_EMAIL>|${ALERT_EMAIL}|g" \
  -e "s|<GMAIL_APP_PASSWORD>|${ALERT_SMTP_PASSWORD}|g" \
  "$TEMPLATE")"

kubectl create secret generic alertmanager-config-email \
  --namespace monitoring \
  --from-literal="alertmanager.yaml=${RENDERED}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Creating Secret/grafana-smtp-credentials..."

kubectl create secret generic grafana-smtp-credentials \
  --namespace monitoring \
  --from-literal="GF_SMTP_USER=${ALERT_EMAIL}" \
  --from-literal="GF_SMTP_PASSWORD=${ALERT_SMTP_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "==> Secrets created. Apply monitoring stack to activate:"
echo "    make apply-monitoring"
echo ""
echo "==> Then run a test alert:"
echo "    kubectl exec -n monitoring deploy/alertmanager-operated -- \\"
echo "      amtool alert add alertname=TestAlert severity=warning namespace=starstalk"
