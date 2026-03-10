.PHONY: help plan apply destroy bootstrap-k3s merge-kubeconfig \
        status ssh logs seed-runner-env setup-runner \
        renew-teleport-bot setup-vault-dev \
        apply-monitoring create-grafana-sa setup-alert-email \
        setup-loki upgrade-loki \
        setup-minio minio-status minio-console \
        setup-agents setup-ollama setup-bug-watcher setup-monitor \
        setup-adguard setup-coredns setup-cert-manager setup-vault-pki \
        setup-network-policies apply-network-policies \
        setup-cnpg-backup cnpg-backup-now update-node-dns \
        security-status setup-security

TERRAFORM_DIR := terraform/environments/homelab
TSH_PROXY     ?= teleport.starstalk.io
TSH_IDENTITY  ?= $(HOME)/.local/share/tbot/identity/identity
NODE          ?=
SERVICE       ?= starstalk

## help: Show available targets
help:
	@sed -n 's/^## //p' $(MAKEFILE_LIST) | column -t -s ':' | sed -e 's/^/  /'

# ── Terraform ─────────────────────────────────────────────────────────────────

## plan: Terraform plan (homelab)
plan:
	terraform -chdir=$(TERRAFORM_DIR) plan

## apply: Terraform apply (homelab)
apply:
	terraform -chdir=$(TERRAFORM_DIR) apply

## destroy: Terraform destroy (homelab)
destroy:
	terraform -chdir=$(TERRAFORM_DIR) destroy

## output: Show Terraform outputs
output:
	terraform -chdir=$(TERRAFORM_DIR) output

# ── k3s ───────────────────────────────────────────────────────────────────────

## bootstrap-k3s: Install k3s on control + workers via tsh (requires k3sup)
bootstrap-k3s:
	TSH_PROXY=$(TSH_PROXY) TSH_IDENTITY=$(TSH_IDENTITY) ./scripts/bootstrap-k3s.sh

## merge-kubeconfig: Merge homelab kubeconfig into ~/.kube/config
merge-kubeconfig:
	./scripts/kubeconfig-merge.sh

# ── Node access ───────────────────────────────────────────────────────────────

## status: List all Teleport-registered nodes
status:
	tsh ls --proxy=$(TSH_PROXY) -i $(TSH_IDENTITY)

## ssh: Open interactive SSH to a node  (NODE=starstalk-runner)
ssh:
	@test -n "$(NODE)" || (echo "Usage: make ssh NODE=<hostname>" && exit 1)
	tsh ssh --proxy=$(TSH_PROXY) -i $(TSH_IDENTITY) root@$(NODE)

## logs: Tail systemd logs on a node    (NODE=starstalk-runner SERVICE=starstalk)
logs:
	@test -n "$(NODE)" || (echo "Usage: make logs NODE=<hostname> [SERVICE=<name>]" && exit 1)
	tsh ssh --proxy=$(TSH_PROXY) -i $(TSH_IDENTITY) root@$(NODE) \
		journalctl -fu $(SERVICE)

## restart: Restart a service on a node (NODE=starstalk-runner SERVICE=starstalk)
restart:
	@test -n "$(NODE)" || (echo "Usage: make restart NODE=<hostname> [SERVICE=<name>]" && exit 1)
	tsh ssh --proxy=$(TSH_PROXY) -i $(TSH_IDENTITY) root@$(NODE) \
		systemctl restart $(SERVICE)

# ── Node setup ────────────────────────────────────────────────────────────────

## seed-runner-env: Create /etc/starstalk/starstalk.env on the runner (fixes crash-loop)
seed-runner-env:
	TSH_PROXY=$(TSH_PROXY) TSH_IDENTITY=$(TSH_IDENTITY) ./scripts/seed-runner-env.sh

## setup-runner: Register GitHub Actions runner on starstalk-runner
setup-runner:
	TSH_PROXY=$(TSH_PROXY) TSH_IDENTITY=$(TSH_IDENTITY) ./scripts/setup-runner.sh

## install-k8s-tools: Install kubectl + helm on the runner node
install-k8s-tools:
	TSH_PROXY=$(TSH_PROXY) TSH_IDENTITY=$(TSH_IDENTITY) \
		./scripts/run-on-node.sh starstalk-runner scripts/node/install-k8s-tools.sh

## renew-teleport-bot: Re-join tbot after cert expiry  (TOKEN=<new-join-token>)
renew-teleport-bot:
	TOKEN=$(TOKEN) ./scripts/renew-teleport-bot.sh

## setup-vault-dev: Copy prod Vault config → secret/starstalk-dev with ENVIRONMENT=dev (run on Vault VM)
## setup-vault-dev: Usage: scp scripts/setup-vault-dev-path.sh root@192.168.0.74:/tmp/ && ssh root@192.168.0.74 bash /tmp/setup-vault-dev-path.sh
setup-vault-dev:
	@echo "Run on Vault VM (192.168.0.74) as root:"
	@echo "  scp scripts/setup-vault-dev-path.sh root@192.168.0.74:/tmp/"
	@echo "  ssh root@192.168.0.74 bash /tmp/setup-vault-dev-path.sh"
	@echo ""
	@echo "Then add VAULT_DEV_ROLE_ID + VAULT_DEV_SECRET_ID to ai_infra GitHub Secrets."

## install-build-tools: Install Go + Docker on the runner (enables self-hosted CI builds)
install-build-tools:
	TSH_PROXY=$(TSH_PROXY) TSH_IDENTITY=$(TSH_IDENTITY) \
		./scripts/run-on-node.sh starstalk-runner scripts/node/install-build-tools.sh

# ── Kubernetes stack ──────────────────────────────────────────────────────────

KUBECONFIG ?= $(CURDIR)/kubeconfig

## setup-k8s: Bootstrap full prod k8s stack (CloudNativePG + Prometheus + starstalk)
setup-k8s:
	KUBECONFIG=$(KUBECONFIG) ./scripts/setup-k8s.sh

## setup-k8s-dev: Bootstrap dev stack (starstalk-dev namespace + dev PostgreSQL)
setup-k8s-dev:
	KUBECONFIG=$(KUBECONFIG) ./scripts/setup-k8s-dev.sh

## setup-github-envs: Create dev + prod GitHub Environments (run once per repo)
setup-github-envs:
	./scripts/setup-github-environments.sh

# ── Kubernetes status ─────────────────────────────────────────────────────────

## k8s-status: Show nodes and all pods
k8s-status:
	KUBECONFIG=$(KUBECONFIG) kubectl get nodes -o wide
	KUBECONFIG=$(KUBECONFIG) kubectl get pods -A

## pg-status: Show prod CloudNativePG cluster status
pg-status:
	KUBECONFIG=$(KUBECONFIG) kubectl get cluster -n starstalk
	KUBECONFIG=$(KUBECONFIG) kubectl get pods -n starstalk -l cnpg.io/cluster=starstalk-pg

## pg-status-dev: Show dev PostgreSQL status
pg-status-dev:
	KUBECONFIG=$(KUBECONFIG) kubectl get cluster -n starstalk-dev
	KUBECONFIG=$(KUBECONFIG) kubectl get pods -n starstalk-dev

## pg-failover: Manually trigger PostgreSQL failover (promotes standby to primary)
pg-failover:
	KUBECONFIG=$(KUBECONFIG) kubectl cnpg promote starstalk-pg -n starstalk

## helm-diff: Show pending Helm changes for prod before deploy (requires helm-diff plugin)
helm-diff:
	KUBECONFIG=$(KUBECONFIG) helm diff upgrade starstalk helm/starstalk \
		--namespace starstalk \
		-f helm/starstalk/values-homelab.yaml

## helm-diff-dev: Show pending Helm changes for dev
helm-diff-dev:
	KUBECONFIG=$(KUBECONFIG) helm diff upgrade starstalk-dev helm/starstalk \
		--namespace starstalk-dev \
		-f helm/starstalk/values-dev.yaml

# ── Monitoring ────────────────────────────────────────────────────────────────

## setup-loki: Install or upgrade Loki + Promtail (centralized log aggregation)
setup-loki: upgrade-loki apply-monitoring

## upgrade-loki: Helm upgrade Loki + Promtail with values from k8s/monitoring/loki-values.yaml
upgrade-loki:
	helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
	helm repo update grafana
	KUBECONFIG=$(KUBECONFIG) helm upgrade --install loki grafana/loki \
		--namespace monitoring \
		-f k8s/monitoring/loki-values.yaml \
		--wait --timeout=5m
	KUBECONFIG=$(KUBECONFIG) helm upgrade --install promtail grafana/promtail \
		--namespace monitoring \
		-f k8s/monitoring/promtail-values.yaml \
		--wait --timeout=3m
	@echo "Loki + Promtail upgraded. Query logs at grafana.starstalk.io → Explore → Loki"

## apply-monitoring: Apply dashboards + alert rules + Loki datasource (idempotent)
apply-monitoring:
	KUBECONFIG=$(KUBECONFIG) kubectl apply -f k8s/monitoring/dashboards/
	KUBECONFIG=$(KUBECONFIG) kubectl apply -f k8s/monitoring/alerts/
	KUBECONFIG=$(KUBECONFIG) kubectl apply -f k8s/monitoring/loki-datasource-cm.yaml

## setup-alert-email: Create k8s Secrets for Alertmanager + Grafana SMTP (reads from .alert-creds)
setup-alert-email:
	KUBECONFIG=$(KUBECONFIG) ./scripts/setup-alert-email.sh

## create-grafana-sa: Create Grafana automation service account + store token as k8s secret
create-grafana-sa:
	KUBECONFIG=$(KUBECONFIG) ./scripts/create-grafana-service-account.sh

## sync-tbot-identity: Pull fresh tbot identity from k8s Secret to WSL2
sync-tbot-identity:
	KUBECONFIG=$(KUBECONFIG) ./scripts/sync-tbot-identity.sh

## install-tbot-sync-timer: Install systemd timer to auto-refresh tbot identity every 30m
install-tbot-sync-timer:
	KUBECONFIG=$(KUBECONFIG) ./scripts/install-tbot-sync-timer.sh

## deploy-tbot-k8s: Deploy tbot inside k3s (kubernetes join method — no token ever needed)
deploy-tbot-k8s:
	KUBECONFIG=$(KUBECONFIG) kubectl apply -f k8s/teleport/

# ── MinIO ─────────────────────────────────────────────────────────────────────

# ── Local AI agents (WSL2) ────────────────────────────────────────────────────

## setup-agents: Install all local AI agents (Ollama + bug-watcher + monitor)
setup-agents:
	bash agents/setup.sh

## setup-ollama: Install Ollama + pull models (RTX 3060, CUDA via WSL2)
setup-ollama:
	bash agents/ollama/setup.sh

## setup-bug-watcher: Build + install bug-watcher daemon (local LLM branch poller)
setup-bug-watcher:
	bash agents/bug-watcher/setup.sh

## setup-monitor: Build + install monitor agent (infra health watcher)
setup-monitor:
	bash agents/monitor/setup.sh

# ── MinIO ─────────────────────────────────────────────────────────────────────

## setup-minio: Deploy distributed MinIO to k3s (4 pods, erasure coding EC:2)
setup-minio:
	KUBECONFIG=$(KUBECONFIG) ./scripts/setup-minio.sh

## minio-status: Show MinIO pod and StatefulSet status
minio-status:
	KUBECONFIG=$(KUBECONFIG) kubectl get statefulset,pods -n minio -l app.kubernetes.io/name=minio

## minio-console: Port-forward MinIO console to localhost:9001
minio-console:
	@echo "Opening MinIO console at http://localhost:9001 (Ctrl-C to stop)"
	KUBECONFIG=$(KUBECONFIG) kubectl port-forward svc/minio -n minio 9001:9001

# ── Security / TLS / DNS ──────────────────────────────────────────────────────

## setup-security: Run all security bootstrap steps in order (idempotent)
setup-security: setup-adguard setup-coredns apply-network-policies setup-cert-manager setup-cnpg-backup
	@echo ""
	@echo "Security baseline complete. Remaining manual steps:"
	@echo "  1. Renew Teleport certs: make renew-teleport-bot"
	@echo "  2. Enable Vault PKI:     make setup-vault-pki"
	@echo "  3. Apply Vault issuer:   kubectl apply -f k8s/cert-manager/issuer-vault-pki.yaml"
	@echo "  4. Update node DNS:      make update-node-dns"

## setup-adguard: Deploy AdGuard Home on ai-knowledge-storage (192.168.0.96) as LAN DNS
setup-adguard:
	TSH_PROXY=$(TSH_PROXY) TSH_IDENTITY=$(TSH_IDENTITY) bash agents/adguard/setup.sh

## setup-coredns: Apply coredns-custom ConfigMap (starstalk.internal zone in k3s)
setup-coredns:
	KUBECONFIG=$(KUBECONFIG) kubectl apply -f k8s/coredns/coredns-custom.yaml
	@echo "CoreDNS will hot-reload within 30s. Test: kubectl run -it --rm dns-test --image=busybox --restart=Never -- nslookup vault.starstalk.internal"

## setup-cert-manager: Install cert-manager + Let's Encrypt ClusterIssuer (requires .cloudflare-creds)
setup-cert-manager:
	KUBECONFIG=$(KUBECONFIG) ./scripts/setup-cert-manager.sh

## setup-vault-pki: Enable Vault PKI engine + create internal CA (requires valid Teleport certs)
setup-vault-pki:
	./scripts/setup-vault-pki.sh

## apply-network-policies: Apply NetworkPolicies to all namespaces
apply-network-policies:
	KUBECONFIG=$(KUBECONFIG) kubectl apply -f k8s/network-policies/
	@echo "NetworkPolicies applied to: starstalk, starstalk-dev, minio, monitoring"

## setup-cnpg-backup: Configure CNPG continuous WAL archiving + base backups to MinIO
setup-cnpg-backup:
	KUBECONFIG=$(KUBECONFIG) ./scripts/setup-cnpg-backup.sh

## cnpg-backup-now: Trigger an immediate CNPG base backup
cnpg-backup-now:
	@printf '%s\n' \
	  'apiVersion: postgresql.cnpg.io/v1' \
	  'kind: Backup' \
	  'metadata:' \
	  '  name: starstalk-pg-backup-'"$$(date +%Y%m%d%H%M)" \
	  '  namespace: starstalk' \
	  'spec:' \
	  '  cluster:' \
	  '    name: starstalk-pg' \
	  '  method: barmanObjectStore' \
	  | KUBECONFIG=$(KUBECONFIG) kubectl apply -f -

## update-node-dns: Point k3s node /etc/resolv.conf at AdGuard Home (192.168.0.96)
update-node-dns:
	SSH_KEY=$(HOME)/.ssh/github_wsl ./scripts/update-node-dns.sh

## security-status: Show status of all security components
security-status:
	@echo "=== cert-manager ==="
	KUBECONFIG=$(KUBECONFIG) kubectl get clusterissuer 2>/dev/null || echo "Not installed"
	@echo ""
	@echo "=== NetworkPolicies ==="
	KUBECONFIG=$(KUBECONFIG) kubectl get networkpolicy -A
	@echo ""
	@echo "=== CNPG Backup ==="
	KUBECONFIG=$(KUBECONFIG) kubectl get cluster starstalk-pg -n starstalk \
		-o jsonpath='Archiving={.status.conditions[?(@.type=="ContinuousArchiving")].status}{"\n"}' 2>/dev/null
	@echo ""
	@echo "=== Certificates ==="
	KUBECONFIG=$(KUBECONFIG) kubectl get certificate -A 2>/dev/null || echo "No certificates yet"
