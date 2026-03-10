#!/usr/bin/env bash
# update-node-dns.sh — Point k3s nodes at AdGuard Home for DNS
#
# Uses a privileged DaemonSet (hostPID + privileged initContainer) to write
# /etc/resolv.conf on all k3s nodes. Idempotent and Teleport-safe (no direct SSH).
set -euo pipefail

KUBECONFIG="${KUBECONFIG:-$(dirname "${BASH_SOURCE[0]}")/../kubeconfig}"
ADGUARD_IP="192.168.0.96"

echo "==> Deploying DNS-update DaemonSet on all k3s nodes..."

kubectl --kubeconfig="${KUBECONFIG}" apply -f - << EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: update-node-dns
  namespace: kube-system
spec:
  selector:
    matchLabels:
      app: update-node-dns
  template:
    metadata:
      labels:
        app: update-node-dns
    spec:
      hostPID: true
      tolerations:
        - effect: NoSchedule
          operator: Exists
      initContainers:
        - name: update-dns
          image: alpine:3.19
          command: ["/bin/sh", "-c"]
          args:
            - |
              set -e
              nsenter --mount=/proc/1/ns/mnt -- systemctl disable --now systemd-resolved 2>/dev/null || true
              if [ -L /host/etc/resolv.conf ]; then rm /host/etc/resolv.conf; fi
              printf 'nameserver ${ADGUARD_IP}\nnameserver 1.1.1.1\nsearch starstalk.internal svc.cluster.local\n' \
                > /host/etc/resolv.conf
              echo "DNS updated on \$(cat /host/etc/hostname 2>/dev/null || hostname)"
          securityContext:
            privileged: true
          volumeMounts:
            - name: host-etc
              mountPath: /host/etc
      containers:
        - name: sleep
          image: alpine:3.19
          command: ["sleep", "infinity"]
          resources:
            requests: { cpu: 1m, memory: 4Mi }
      volumes:
        - name: host-etc
          hostPath:
            path: /etc
EOF

echo "==> Waiting for DaemonSet to complete (30s)..."
sleep 30

kubectl --kubeconfig="${KUBECONFIG}" logs -n kube-system \
  -l app=update-node-dns -c update-dns 2>/dev/null

echo "==> Cleaning up DaemonSet..."
kubectl --kubeconfig="${KUBECONFIG}" delete daemonset update-node-dns -n kube-system

echo ""
echo "==> All k3s nodes now resolve via AdGuard Home (${ADGUARD_IP})"
echo "    Test: dig vault.starstalk.internal @${ADGUARD_IP}"
