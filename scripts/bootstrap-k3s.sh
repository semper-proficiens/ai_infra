#!/usr/bin/env bash
# bootstrap-k3s.sh — install k3s over Teleport SSH (tbot certs)
#
# Prerequisites:
#   1. terraform apply completed — k3s VMs are up and registered in Teleport
#   2. tbot running with tbot.yaml — certs in ./tbot/output/
#   3. tsh login completed — active session
#   4. k3sup installed: https://github.com/alexellis/k3sup#download-k3sup
#
# Usage:
#   CLUSTER=<your-teleport-cluster-name> ./scripts/bootstrap-k3s.sh
#
set -euo pipefail

CLUSTER="${CLUSTER:-$(tsh status --format=json | jq -r '.active.cluster')}"
CONTROL_IP=$(terraform -chdir=terraform/environments/homelab output -raw k3s_control_ip)
WORKER_COUNT=$(terraform -chdir=terraform/environments/homelab output -raw worker_count)

echo "==> Cluster:      ${CLUSTER}"
echo "==> Control IP:   ${CONTROL_IP}"
echo "==> Worker count: ${WORKER_COUNT}"
echo ""

# Install k3s on control plane
echo "==> Installing k3s control plane on k3s-control (${CONTROL_IP})..."
k3sup install \
  --host "k3s-control" \
  --user root \
  --ssh-options "-o ProxyCommand='tsh proxy ssh --cluster=${CLUSTER} %r@%h:%p'" \
  --local-path ./kubeconfig \
  --context homelab

echo "==> Control plane installed. kubeconfig written to ./kubeconfig"
echo ""

# Join each worker
for i in $(seq 0 $((WORKER_COUNT - 1))); do
  WORKER_HOSTNAME="k3s-worker-${i}"
  echo "==> Joining ${WORKER_HOSTNAME} to cluster..."
  k3sup join \
    --host "${WORKER_HOSTNAME}" \
    --server-host "k3s-control" \
    --user root \
    --ssh-options "-o ProxyCommand='tsh proxy ssh --cluster=${CLUSTER} %r@%h:%p'"
  echo "    Done."
done

echo ""
echo "==> k3s bootstrap complete!"
echo "    Merge kubeconfig: ./scripts/kubeconfig-merge.sh"
echo "    Test:             KUBECONFIG=./kubeconfig kubectl get nodes"
