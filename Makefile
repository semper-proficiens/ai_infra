.PHONY: help plan apply destroy bootstrap-k3s merge-kubeconfig \
        status ssh logs seed-runner-env setup-runner \
        renew-teleport-bot setup-vault-dev \
        apply-monitoring create-grafana-sa

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

## apply-monitoring: Apply dashboards + alert rules (idempotent)
apply-monitoring:
	KUBECONFIG=$(KUBECONFIG) kubectl apply -f k8s/monitoring/dashboards/
	KUBECONFIG=$(KUBECONFIG) kubectl apply -f k8s/monitoring/alerts/

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
