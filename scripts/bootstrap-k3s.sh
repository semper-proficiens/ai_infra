#!/usr/bin/env bash
# bootstrap-k3s.sh — install k3s on control + worker nodes
#
# Uses direct SSH (injected key from Terraform cloud-init) since nodes are not
# yet in Teleport at bootstrap time. After bootstrap, install Teleport separately.
#
# Prerequisites:
#   1. terraform apply completed — k3s VMs are up with cloud-init SSH key injected
#   2. k3sup installed: https://github.com/alexellis/k3sup#download-k3sup
#   3. SSH key loaded: eval "$(ssh-agent -s)" && ssh-add ~/.ssh/github_wsl
#
# Usage:
#   eval "$(ssh-agent -s)" && ssh-add ~/.ssh/github_wsl
#   ./scripts/bootstrap-k3s.sh
#
set -euo pipefail

SSH_KEY="${SSH_KEY:-${HOME}/.ssh/github_wsl}"
SSH_USER="${SSH_USER:-ubuntu}"

CONTROL_IP=$(terraform -chdir=terraform/environments/homelab output -raw k3s_control_ip)
WORKER_IPS=$(terraform -chdir=terraform/environments/homelab output -json worker_ips | python3 -c "import sys,json; [print(ip) for ip in json.load(sys.stdin)]")

echo "==> Control IP:   ${CONTROL_IP}"
echo "==> Worker IPs:   ${WORKER_IPS}"
echo "==> SSH user:     ${SSH_USER}"
echo "==> SSH key:      ${SSH_KEY}"
echo ""

# Install k3s on control plane
echo "==> Installing k3s control plane on ${CONTROL_IP}..."
k3sup install \
  --ip "${CONTROL_IP}" \
  --user "${SSH_USER}" \
  --ssh-key "${SSH_KEY}" \
  --local-path ./kubeconfig \
  --context homelab \
  --k3s-extra-args '--disable traefik'

echo "==> Control plane installed. kubeconfig written to ./kubeconfig"
echo ""

# Join each worker
while IFS= read -r WORKER_IP; do
  echo "==> Joining worker ${WORKER_IP} to cluster..."
  k3sup join \
    --ip "${WORKER_IP}" \
    --server-ip "${CONTROL_IP}" \
    --user "${SSH_USER}" \
    --ssh-key "${SSH_KEY}"
  echo "    Done."
done <<< "${WORKER_IPS}"

echo ""
echo "==> k3s bootstrap complete!"
echo "    Merge kubeconfig: make merge-kubeconfig"
echo "    Test:             KUBECONFIG=./kubeconfig kubectl get nodes -o wide"
