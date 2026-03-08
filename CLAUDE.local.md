# Local Development Context

## Memory Configuration
- Memory backend: LOCAL SQLite-like JSON (.swarm/session-knowledge.json)
- Future endpoint: ai-fleet-memory.starstalk.io
- FLEET_MEMORY_URL: not yet configured

## Local Environment
- WSL2 Ubuntu 24.04 on Windows 11
- Node.js 18+ (upgrade to 20+ for ruflo)
- Go 1.23 toolchain for backend
- Flutter SDK for frontend
- Python 3.12 for code-redactor hook

## Multi-Session Coordination (MANDATORY)

Multiple Claude Code sessions may run in parallel. Follow all three tiers to prevent collisions.

### Tier 1 — Git Worktrees (file isolation)
- For any feature, fix, or multi-file task: use `EnterWorktree` before touching files
- Never work directly on `main` for anything beyond a single-line fix

### Tier 2 — RuVector Claims (shared resource locking)
**Before editing any file:**
1. `claims_claim(key="file:<repo-relative-path>", owner="<one-line session description>")`
2. If claim already held → `claims_board` → wait, coordinate, or `claims_steal` if idle >30 min
3. After committing → `claims_release(key="file:<repo-relative-path>")`

**Before starting any multi-file task:**
1. `claims_claim(key="task:<brief-slug>", owner="<session description>")`
2. `claims_list` to check what other sessions own — adjust scope to avoid overlap

### Tier 3 — Coordination Sync (context freshness)
**After committing any file change:**
- `coordination_sync` with `{ changed: ["<file-path>"], by: "<session-desc>", branch: "<branch>" }`

**At session start when joining an active codebase:**
- Call `coordination_sync` (read mode) to check for recent broadcasts
- Re-read any files flagged as changed before reasoning about them

## Session Behavior (applies to every session)
<!-- These instructions override default Claude caution for this project -->
- **Autonomous execution**: Do not stop mid-task to ask for confirmation. Run to completion or until a hard permission error occurs.
- **Iterate on failures**: If a step fails, diagnose and retry with a fix before surfacing to the user. Only escalate if stuck after 2-3 attempts or if the fix requires a decision.
- **Credentials**: `.proxmox-creds` and `.github-creds` are always available — read them when needed without asking.
- **RuVector**: Search memory before every response. Store every architectural decision, bug found, or pattern established.
- **Scope**: All local file edits, `tsh ssh` via claude-bot-wsl2 to all nodes, Proxmox API calls, and GitHub API calls with tokens in creds files are pre-authorized for the duration of any session.
- **Tool approvals**: `settings.local.json` grants `Bash(*)`, `Edit(*)`, `Write(*)`, `Read(*)`, `Glob(*)`, `Grep(*)`, `WebFetch(*)`, `Task(*)` and all claude-flow MCP tools — no per-tool confirmation needed.

## Infrastructure Config
<!-- Static — edit manually, never auto-populated -->

### ssj1 — primary Proxmox (192.168.0.69)
- API: https://192.168.0.69:8006
- Proxmox token: automation@pve!claude-code (secret in .proxmox-creds as PROXMOX_TOKEN)
- Node name: test
- Disk storage: local-lvm (lvmthin, rootdir+images, 140GB free)
- Template storage: local (dir, has vztmpl)
- Network bridge: vmbr0 (cidr 192.168.0.69/24)

### ssj2 — second Proxmox (192.168.0.84)
- API: https://192.168.0.84:8006
- Proxmox token: automation@pve!claude-code (secret in .proxmox-creds as PROXMOX_TOKEN_SSJ2)
- Node name: pve (confirm in ssj2 web UI if different)
- Create token: Datacenter → Permissions → API Tokens → Add → grant same role as ssj1

### VMs / LXCs (all managed by Terraform except legacy VMs)
| Hostname | VMID | IP | Host | Role | Terraform |
|---|---|---|---|---|---|
| starstalk-runner | 110 | 192.168.0.77 | ssj1 | GitHub Actions runner | yes (import) |
| k3s-control | 120 | 192.168.0.80 | ssj1 | k3s control plane | yes |
| k3s-worker-0 | 121 | 192.168.0.81 | ssj1 | k3s worker | yes |
| k3s-worker-1 | 122 | 192.168.0.82 | ssj2 | k3s worker (cross-host HA) | yes |
| starstalk-goapp | - | 192.168.0.98 | ssj1 | legacy backend VM → retiring | no |
| starstalk-postgres | - | 192.168.0.173 | ssj1 | legacy DB VM → retiring | no |

### Default LXC OS template
local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst

### Rule: all new VMs/LXCs go through Terraform
When deploying a new service, determine which Proxmox host best fits hardware requirements (ask user if unsure), then add it to terraform/environments/homelab/proxmox.tf and run `make apply`.

## Cloudflare API Config
- Credentials: `.cloudflare-creds` (gitignored) — CF_API_TOKEN + CF_EMAIL
- Account ID: 4b38e02059765f0c07c744b753ccf516
- Zone ID (starstalk.io): 841f4e9ed09e859d010305b019d983c1
- **Permitted CF API operations**: DNS record CRUD, Tunnel CRUD, Access app+policy CRUD

## Target Architecture (starstalk backend + DB)
<!-- Updated 2026-03-07 -->
- **Backend**: k3s Deployment, 2 replicas (HPA min 2, max 6), pod anti-affinity across nodes
- **PostgreSQL**: CloudNativePG 2-instance cluster — primary on k3s-worker-0 (ssj1), standby on k3s-worker-1 (ssj2)
  - Auto-failover in ~30s if primary crashes
  - DB service: `starstalk-pg-rw.starstalk.svc` (rw), `starstalk-pg-ro.starstalk.svc` (read-only)
- **Image registry**: ghcr.io/semper-proficiens/starstalk-backend:<tag>
- **Deploy**: `git tag vX.Y.Z && git push origin vX.Y.Z` → Docker build → GHCR push → helm upgrade
- **Monitoring**: kube-prometheus-stack (Prometheus + Grafana at grafana.starstalk.io)
- **Recovery from scratch**: `make apply && make bootstrap-k3s && make setup-k8s`

### Dev vs Prod environments
| | Dev | Prod |
|---|---|---|
| Namespace | `starstalk-dev` | `starstalk` |
| Trigger | push to `dev` branch (auto) | `v*` tag + manual approval |
| Replicas | 1, no HPA | 2, HPA 2-6 |
| PostgreSQL | CloudNativePG 1 instance, 5Gi | CloudNativePG 2 instances (HA), 20Gi |
| Ingress | api-dev.starstalk.io | api.starstalk.io |
| Image tag | `dev` (always latest) | `v1.2.3` (semver) |

**Promotion flow:** push to `dev` → auto-deploys to dev → verify in app → create tag → GitHub shows approval gate → approve → prod deploys.

### CI/CD cost model (zero ubuntu-latest minutes in private repo)
| Job | Runner | Repo | Cost |
|---|---|---|---|
| go test / go vet | self-hosted proxmox | starstalk (private) | free |
| docker build + push | self-hosted proxmox | starstalk (private) | free |
| dispatch trigger | self-hosted proxmox | starstalk (private) | free |
| helm deploy (dev/prod) | self-hosted proxmox | ai_infra (public) | free |
The runner LXC has `nesting=true` (Terraform) enabling Docker. Go + Docker installed via `make install-build-tools`. Secret split: build secrets (GITHUB_TOKEN for GHCR) in starstalk; deploy secrets (KUBECONFIG_HOMELAB, VAULT_*) in ai_infra. The only value that crosses the boundary: image tag string.

### Required GitHub Secrets
| Secret | Repo | Purpose |
|---|---|---|
| `AI_INFRA_DISPATCH_TOKEN` | starstalk | PAT (Actions:write on ai_infra) to trigger deploy workflow |
| `KUBECONFIG_HOMELAB` | ai_infra | base64 kubeconfig for k3s cluster |
| `VAULT_ROLE_ID` | ai_infra | Vault AppRole role ID |
| `VAULT_SECRET_ID` | ai_infra | Vault AppRole secret ID |
| `VAULT_ROLE_ID` | starstalk | (keep for legacy binary deploy fallback) |
| `VAULT_SECRET_ID` | starstalk | (keep for legacy binary deploy fallback) |

### Pending one-time actions
0. ✅ `make install-build-tools` → Go + Docker installed on runner LXC
1. ✅ `make apply` → provisioned k3s-control (120, 192.168.0.80) + k3s-worker-0 (121, 192.168.0.81) on ssj1; runner LXC (110) imported
2. ✅ `make bootstrap-k3s` → k3s v1.34.5 installed; cluster Ready (2 nodes)
3. ✅ KUBECONFIG_HOMELAB uploaded to ai_infra GitHub repo
4. ✅ `make install-k8s-tools` → kubectl v1.31.0 + helm v3.16.0 already on runner
5. ✅ `make setup-github-envs` → dev (auto, dev-branch only) + prod (nubesFilius approval) environments created
6. ✅ `make setup-k8s` → CloudNativePG (2-instance, healthy) + kube-prometheus-stack + starstalk Helm installed; pods in ImagePullBackOff pending first CI image push
7. ✅ `make setup-k8s-dev` → starstalk-dev namespace + CloudNativePG dev (1-instance) + starstalk-dev Helm installed
   - ghcr-pull-secret created in both namespaces; imagePullSecrets added to values-homelab.yaml + values-dev.yaml
8. ✅ Data migrated: pg_dump from starstalk-postgres (192.168.0.173) → pg_restore into starstalk-pg-1 (CloudNativePG). 29 tables. starstalk app user granted full access.
9. ✅ Vault updated: DB_HOST=starstalk-pg-rw.starstalk.svc.cluster.local, DB_USER=starstalk, DB_PASSWORD=new, INFRA=k8s (version 25)
10. ✅ Traefik installed in k3s (helm, kube-system, NodePort 80:31423/443:30507)
11. ✅ CF Tunnel k3s-homelab created (ID: 24d3895b-efed-47ec-8d7a-9c74080c9cdc), cloudflared Deployment running (2 pods, kube-system). Token in Secret cloudflared-tunnel-token.
    Ingress rules: api.starstalk.io + api-dev.starstalk.io + grafana.starstalk.io + monitor.starstalk.io → traefik.kube-system.svc.cluster.local:80
12. ✅ DNS CUTOVER complete (2026-03-08):
    - api.starstalk.io → 24d3895b-efed-47ec-8d7a-9c74080c9cdc.cfargotunnel.com (record id: 064ae86aa6626977ef4575ea07e3f80c)
    - api-dev.starstalk.io → same tunnel (new record created)
    - grafana.starstalk.io → same tunnel (new record created)
    - Traffic verified: 200 from api.starstalk.io, Grafana login redirect working
    - Traefik configured with --serversTransport.insecureSkipVerify=true (backend serves HTTPS)
    - v2 routing: api.starstalk.io/v2/* → starstalk-v2 k8s service (port 8082, path-based via Traefik Ingress). No extra DNS needed.
13. ✅ Retire old VMs — COMPLETE (2026-03-08):
    - starstalk-goapp (LXC VMID 106): service stopped, LXC destroyed from Proxmox
    - starstalk-postgres (LXC VMID 104): postgresql stopped, LXC destroyed from Proxmox
    - tbot fixed via k3s kubernetes join method (see tbot-deployment.yaml)
14. (Later) Add ssj2 Proxmox token → add k3s-worker-1 on ssj2 for cross-host HA

### Known issues / TODOs
- ✅ **AI_INFRA_DISPATCH_TOKEN**: Resolved — switched starstalk CI from repository_dispatch to gh workflow run (workflow_dispatch). No new PAT needed.
- ✅ **Vault dev path**: DONE (2026-03-08) — script ran on Vault VM, `VAULT_DEV_ROLE_ID` + `VAULT_DEV_SECRET_ID` added to ai_infra GitHub Secrets. Next: revert values-dev.yaml service.port→8080, probes→httpGet on /health:8080.
- ✅ **Teleport certs**: FIXED — tbot now runs in k3s with kubernetes join method (k8s/teleport/). Auto-renews via identity-sync sidecar → tbot-sync systemd timer on WSL2.
- ✅ **Legacy VM retirement**: DONE (2026-03-08) — starstalk-goapp (VMID 106) and starstalk-postgres (VMID 104) stopped and destroyed from Proxmox.
- **Helm health probe**: TCP probe on 443 is a workaround while dev uses prod Vault path. Once dev AppRole reads `secret/starstalk-dev`, app will bind 8080 (HTTP) and probes should switch to httpGet on /health:8080.
- **k3s-control RAM**: Bumped 2GB→4GB in Terraform (2026-03-08). Terraform apply in progress — VM restart required to apply. Monitor NodeHighMemory alert.
- **ai_infra runner**: proxmox-ai-infra-runner registered and running in /home/github-runner-ai-infra on starstalk-runner LXC. deploy-prod jobs need nubesFilius approval gate.
- **starstalk backend.yml**: ios.yml dispatch fixed (--ref dev → --ref main). PR #9 open.

### Operational Runbooks

#### Teleport cert renewal (run when `tsh` returns "cert has expired")
```bash
# Step 1 — On Teleport auth server (192.168.0.199, ssh from ssj2 Proxmox):
tctl bots rm claude-bot-wsl2
tctl bots add claude-bot-wsl2 --roles=bot-node-access --token-ttl 0
# Copy the printed token

# Step 2 — On WSL2:
TOKEN=<token-from-step-1> make renew-teleport-bot
# Script: wipes expired identity, updates ~/.config/tbot.yaml, runs tbot --oneshot, restarts daemon
# Token stored in ~/.config/.teleport-bot-token for future renewals

# Verify:
make status   # should list all nodes
```

#### Vault dev/prod segregation setup (run once on Vault VM)
```bash
# From WSL2 — copy script to Vault VM:
scp scripts/setup-vault-dev-path.sh root@192.168.0.74:/tmp/
ssh root@192.168.0.74 bash /tmp/setup-vault-dev-path.sh
# Script: copies secret/starstalk → secret/starstalk-dev with ENVIRONMENT=dev, PORT=8080
# Creates starstalk-dev-policy + starstalk-dev AppRole (non-expiring secret_id)
# Prints kubectl command + role_id/secret_id to add to GitHub Secrets

# After running: add VAULT_DEV_ROLE_ID + VAULT_DEV_SECRET_ID to ai_infra GitHub Secrets
# Then update values-dev.yaml: service.port=8080, probes=httpGet on /health:8080
# Or: make setup-vault-dev  (prints reminder)
```

#### Deploy manually (while classic PAT is not yet set up)
```bash
# Trigger dev deploy:
gh workflow run deploy-backend.yml --repo semper-proficiens/ai_infra \
  -f environment=dev -f image_tag=dev

# Trigger prod deploy (requires nubesFilius approval in GitHub UI):
gh workflow run deploy-backend.yml --repo semper-proficiens/ai_infra \
  -f environment=prod -f image_tag=<semver-tag>
```

## Node Access (MANDATORY — always tsh, NEVER raw SSH)

**ABSOLUTE RULE: Direct SSH (`ssh`, `scp`) to any node is FORBIDDEN.**
If tsh is broken, FIX TELEPORT FIRST. Do not fall back to direct SSH under any circumstance.
Violation reason: bypasses audit log, access control, and the entire security model.

Teleport renewal process (when certs expire):
1. Ask user to run: `tsh login --proxy=teleport.starstalk.io` in their terminal
2. Once logged in: `tsh ssh root@192.168.0.199` to reach auth server, then `tctl bots add claude-bot-wsl2 --roles=bot-node-access --token-ttl 0`
3. Run: `TOKEN=<token> make renew-teleport-bot`
4. Verify: `make status`

- **Bot**: `claude-bot-wsl2`, identity at `~/.local/share/tbot/identity/identity`
- **Proxy**: `teleport.starstalk.io:443`
- **Auth server**: `192.168.0.199:3025` (port 22 closed — only reachable via tsh)
- **Interactive SSH**: `make ssh NODE=<hostname>`  or  `tsh ssh --proxy=teleport.starstalk.io -i ~/.local/share/tbot/identity/identity root@<hostname>`
- **Run script on node**: `./scripts/run-on-node.sh <node> <script> [VAR=value ...]`
- **List nodes**: `make status`

## Node Setup Scripts
- `make seed-runner-env` — creates `/etc/starstalk/starstalk.env` on runner (fixes crash-loop). Reads VAULT_ROLE_ID + VAULT_SECRET_ID from `.deploy-creds`.
- `make setup-runner` — registers GitHub Actions runner on starstalk-runner. Reads GITHUB_TOKEN from `.github-creds`.
- `make bootstrap-k3s` — installs k3s control + workers via k3sup + tsh proxy
- `make logs NODE=<host> SERVICE=<name>` — tail systemd logs on any node
- `make restart NODE=<host> SERVICE=<name>` — restart a service on any node

## Credential Files (gitignored)
- `.github-creds` — GITHUB_TOKEN (PAT)
- `.proxmox-creds` — Proxmox API token
- `.cloudflare-creds` — CF_API_TOKEN + CF_EMAIL
- `.deploy-creds` — VAULT_ROLE_ID + VAULT_SECRET_ID (see .deploy-creds.example)

## Session Knowledge
This file is auto-appended by the memory capture hook.
Knowledge from previous sessions is loaded via SessionStart hook.

### Accumulated Learnings
<!-- AUTO-POPULATED BY HOOKS - DO NOT EDIT BELOW THIS LINE -->

#### Session 2026-02-26_23:01
- [decisions] 3. **Summarize** the key decisions/restrictions from memory

#### Session 2026-02-26_23:22
- [conventions] - **45 patterns extracted** — architectural patterns, code conventions, API structures
- [decisions] - **69 trajectories evaluated** — decision paths and code flows
- [bugs] - **3 contradictions resolved** — conflicting patterns reconciled

#### Session 2026-02-26_23:26
- [architecture] | 2 | [code] | 0.302 | Go chi/v5 backend with repository->service->handler pattern, PostgreSQL, Vault secrets, S3 storage, dual auth (Google OAuth + internal JWT) |
- [decisions] [code] ranked highest because of the Vault AppRole auth content, while [code] matched on the dual auth (Google OAuth + internal JWT) detail.

#### Session 2026-02-26_23:30
- [bugs] **[code] while loop** (lines 52-64) is the second issue — it spawns a separate [code] process per extracted knowledge entry (up to 20), each doing a read-modify-write on the JSON file.
- [decisions] **Rewrite [code] in Go** — the Python interpreter startup is pure overhead since the logic (regex matching, JSON output) is perfectly suited for Go.
- [bugs] **Fix the [code] while loop** — consolidate the per-entry jq calls into a single call that appends all entries at once.
- [bugs] 2. Fix the [code] while loop to batch all entries in one jq call

#### Session 2026-02-26_23:32
- [decisions] The difference between Go and Rust is ~1-4ms — imperceptible, and dwarfed by the jq/bash subprocess overhead in [code] anyway.
- [decisions] **Practical reasons Go wins here:**
- [bugs] **Verdict:** Go eliminates the real problem (Python startup). Rust would be gold-plating it.

#### Session 2026-02-26_23:42
- [decisions] - [code] as a middle ground still adds ~200ms first-run compile overhead
- [bugs] The only change still worth doing is the [code] while loop fix — that's a pure shell edit, no binary involved.

#### Session 2026-02-26_23:43
- [decisions] - Iterates over entries, filters out any with empty/null summaries

#### Session 2026-02-27_09:45
- [decisions] **Key corrections vs the plan:**

#### Session 2026-02-27_09:56
- [architecture] The Proxmox API is at [code]. Two options:
- [conventions] **Option A — API Token (recommended, no password stored)**

#### Session 2026-02-27_10:03
- [bugs] Here's the minimal Proxmox permission set you need, broken down by use case:
- [decisions] If a specific automation step fails with 403, I can tell you exactly which privilege to add rather than over-granting upfront.

#### Session 2026-02-27_10:19
- [bugs] "No output" from curl is abnormal — likely the response body was empty or it silently errored. Run this instead:
- [bugs] Fix the curl first so we confirm the token actually works before we do anything with it.

#### Session 2026-02-27_10:27
- [conventions] Also — do you have a preferred storage and network bridge on that node? (Usually [code] for storage and [code] for network, but varies.)

#### Session 2026-02-27_10:35
- [decisions] This replaces the narrower [code] and [code] entries (you can delete those). Root path with propagate covers everything. Then tell me:
- [conventions] - What OS template you prefer (Ubuntu 22.04 or 24.04 LXC)

#### Session 2026-02-27_11:01
- [bugs] The upload is silently timing out — routing 600MB through WSL2 → Proxmox is the problem.
- [bugs] The cleanest fix: add one privilege to the role so Proxmox can download the image itself.

#### Session 2026-02-27_16:33
- [decisions] **To summarize where you left off:** You were trying to set up Proxmox with an LXC container, the upload was timing out because of WSL2 → Proxmox routing, and the plan was to let Proxmox pull the image directly.
- [conventions] 1. Your preferred OS template (Ubuntu 22.04 or 24.04)

#### Session 2026-02-27_16:37
- [bugs] - Found: Session context — upload timeout fix pending storage/bridge/OS info

#### Session 2026-02-27_16:43
- [bugs] **The problem with RuVector right now:**
- [decisions] The right solution is a two-layer approach:
- [bugs] - Stored: [bugs] code-redactor.py strips all backtick values to [code], causing session summaries to lose specific config values like hostnames, storage pools, bridge names

#### Session 2026-02-27_17:08
- [bugs] - Found: Prior entries with [code] placeholders — now fixed with static config section

#### Session 2026-02-27_18:33
- [decisions] | Step | Prediction | Reason |
- [bugs] | Gap | Fix needed |
- [bugs] Want me to start on the ones I can fix right now — specifically the [code] systemd service on the runner and checking the health endpoint in the backend code?
- [bugs] - Stored: [bugs] Fine-grained PAT missing Actions:Read + Contents:Read — can't monitor workflow runs via API.

#### Session 2026-02-27_19:17
- [bugs] Both of these are one-time provisioning tasks, not pipeline bugs.

#### Session 2026-02-27_21:00
- [bugs] | [code] | App Store Connect → Keys |
- [bugs] - Found: Prior architecture and bug entries confirming the two gaps

#### Session 2026-02-27_21:03
- [bugs] The problem in CI is that these files normally live in your local Mac's Keychain.
- [decisions] That's why it can be a private repo rather than a secret vault.
- [decisions] Required because GitHub macOS runners are ephemeral and have no Keychain.

#### Session 2026-02-27_21:33
- [bugs] - Parallel independent workstreams (e.g., backend + iOS fix simultaneously) → [code] + multiple [code]
- [decisions] - Stored: nothing new (all decisions are in committed CLAUDE.md)

#### Session 2026-02-27_21:36
- [decisions] - The MCP server runs as a local process; Claude Code communicates with it over stdio
- [decisions] - Stored: nothing (decision documented in commit message and CLAUDE.md)

#### Session 2026-02-27_21:43
- [decisions] **ruflo@latest vs ruflo@alpha:** Both are v3.5.1 right now.
- [conventions] - Prefer ruflo local agents for coordination; Task tool only for high-level analysis
- [decisions] That's the layer that actually governs it contractually.

#### Session 2026-02-28_01:17
- [bugs] Now: the updated [code] detects complex prompts (>20 words, or contains keywords like [code], [code], [code], [code], etc.) and injects a mandatory step 5 requiring [code] → [code] before starting work.
- [bugs] It's impressive for general use, but for your specific situation it has critical problems:
- [decisions] - **CVE-2026-25253** (CVSS 8.8): WebSocket origin bypass allowing RCE.
- [bugs] If those matter for a non-coding personal assistant use case in the future (separate from this codebase), it's worth revisiting once the RCE CVE is patched and the skills registry is audited.
- [decisions] It keeps execution local with traffic over TLS through Anthropic's infrastructure.
- [decisions] - [OpenClaw vs Claude Code: Remote Control Agents – Unite.AI](https:[path])
- [decisions] - [Claude Code Remote Control vs.
- [decisions] - Stored: nothing (all decisions documented in commit and CLAUDE.md)

#### Session 2026-02-28_01:40
- [bugs] - Login screen → enter [code] + your password → JWT issued (24h)

#### Session 2026-02-28_01:56
- [bugs] The 503 ingress error is gone. The two remaining warnings are harmless:
- [bugs] - Searched: cloudflare tunnel ingress rules 503 fix
- [bugs] - Stored: nothing (fix was a one-liner: add [code] to [code] command)

#### Session 2026-02-28_02:07
- [bugs] Specifically looking for lines starting with [code] — those show the raw stream-json events so we can confirm the event format parsing is correct, or fix it if the format differs from what the code expects.
- [bugs] Also watching for any new stderr lines like [code] which will reveal if there's another flag issue.
- [bugs] - Stored: [bugs] Two claude-remote subprocess bugs: (1) [code] flag doesn't exist in claude 2.1.63 — removed; (2) [code] env var must be deleted from child process env to allow claude subprocess to run outside active session

#### Session 2026-02-28_02:36
- [bugs] **Go** is the ideal choice — it's already the project language, [code] is already in use in the backend, and a compiled binary means no [code], no runtime surprises, and proper static typing catches errors before deployment.
- [decisions] **Rust is installed** ([code]), but it's overkill complexity for a WebSocket proxy — the async Tokio boilerplate is heavy for what is essentially a thin wrapper.
- [bugs] Before going down the rewrite path though — I just found the actual root cause of the "no output" issue:
- [bugs] The rewrite question is still valid, but I want to set the right expectation: the current issues were a flag bug, not a language problem.
- [conventions] | **Go** (recommended) | Project language, gorilla/websocket already used, single binary, strong types, fast | Needs [code] first (~2 min) |
- [bugs] | Node.js (current) | Already working, zero install | Dynamic types, npm deps, the bug we just fixed |
- [bugs] - Stored: nothing (root cause was [code] missing from [code])

#### Session 2026-02-28_02:52
- [bugs] | Root bug fixed | [code] missing flag | Same fix, now in typed code |
- [decisions] - Systemd service updated to run [code] instead of [code]

#### Session 2026-02-28_13:04
- [conventions] **Option B — Move claude-remote to the Proxmox runner LXC (recommended)**

#### Session 2026-02-28_13:08
- [bugs] Fix: a Windows Task Scheduler task that launches WSL2 at startup.

#### Session 2026-02-28_13:30
- [conventions] **Option A — Cloudflare Access (recommended)**
- [bugs] Doesn't change who can access it, but removes the URL leakage problem immediately.
- [bugs] Cloudflare Access handles authentication (your Google account is already on your phone), session cookies fix the URL leak.

#### Session 2026-02-28_13:34
- [architecture] 3. Update [code] and RuVector memory so future sessions know CF API is available

#### Session 2026-02-28_16:04
- [decisions] **How it works:** Wraps the local [code] CLI as a subprocess, streams its [code] output over an authenticated WebSocket connection.
- [bugs] - Strips [code]/[code] env vars (prevents "nested session" error)
- [bugs] - Fixed spurious error logs when client disconnects after successful response
- [bugs] **Problem solved:** When your Windows PC sleeps/reboots, all WSL2 services go down. You can now wake it from anywhere in the world with a single tap.

#### Session 2026-02-28_18:32
- [decisions] - **claude-remote** (Go rewrite) was completed and deployed — wraps the local [code] CLI as a subprocess, streams [code] output over an authenticated WebSocket connection
- [bugs] - Two subprocess bugs were fixed: (1) a flag that doesn't exist in claude 2.1.63 was removed, (2) env var stripping to prevent "nested session" error
- [bugs] - Spurious error logs on client disconnect were also fixed
- [bugs] - **wake-server** was set up — solves the problem of WSL2 services going down when Windows sleeps/reboots; accessible at [code] (CF Access + Google auth)

#### Session 2026-02-28_18:35
- [decisions] - Stored: nothing (status check only, no new decisions)

#### Session 2026-02-28_18:39
- [bugs] **On the auto-login / passcode question — two separate issues:**
- [decisions] **1. PIN vs Password in the script**
- [decisions] Yes — this is the trade-off.
- [decisions] For a home machine that's the only WoL path, it's a common and accepted trade-off.
- [decisions] If you want to keep physical security, there's an alternative: instead of auto-login, we can configure WSL2 services to start at **boot** (via Windows startup, before login) using a different mechanism.
- [conventions] What's your preference — accept the no-passcode trade-off, or keep the PIN and find another approach?
- [conventions] - Stored: nothing (user preference pending)

#### Session 2026-02-28_21:16
- [bugs] The auth error persists even with the same token.

#### Session 2026-02-28_22:38
- [bugs] - **Conversation continuity was broken**: [code] prevented sessions from being saved, so [code] on message 2+ found nothing and silently started a fresh conversation.
- [decisions] - **O(n²) rendering eliminated**: instead of [code] on every incoming chunk (which copies the entire accumulated string each time), deltas are buffered in a JS string and flushed to the DOM via [code] — at most 60 updates/sec regardless of how fast chunks arrive.
- [bugs] The fundamental bottleneck (claude CLI startup + MCP server init ~2-5s) is unavoidable without a much bigger architectural change (persistent subprocess), but the above fixes should make the streaming feel noticeably smoother once output starts flowing.

#### Session 2026-03-01_00:15
- [decisions] | [code] | Yes | On session stop: extracts decisions/bugs/patterns from last message → saves to [code] + appends to [code] |
- [bugs] | [code] | Yes | Logs MCP tool calls for debugging |
- [decisions] - What is this project (overview, goals)
- [conventions] - Code conventions (patterns, naming, file structure)
- [conventions] - Any rules you want Claude to always follow
- [decisions] The memory compounds — every session, [code] extracts what was learned (decisions made, bugs found, patterns established) and saves it.

#### Session 2026-03-01_00:20
- [decisions] Good question, and it's worth being precise because the term gets used for very different things.
- [bugs] Orchestrator + worker pattern** — One "orchestrator[string]worker" AIs in parallel.
- [bugs] | Two truly independent workstreams at the same time | Yes | E.g., fix backend bug while simultaneously writing iOS feature — but you'd need two Claude windows anyway |
- [decisions] | Architectural decision with competing approaches | Maybe | [code] gives you a structured "debate" between perspectives |
- [decisions] The overhead of coordination (defining tasks, syncing state, assembling results) usually exceeds the benefit for a solo developer's workflow.
- [decisions] The memory system + hooks you already have gives you more practical value — context persists across sessions, decisions accumulate, patterns are reused.
- [decisions] - Stored: nothing (conceptual explanation, no project-specific decisions)

#### Session 2026-03-01_00:28
- [decisions] Here's what's now set up globally vs what you do per repo:
- [bugs] That creates the three mechanical files ([code], [code], [code]) and patches [code].

#### Session 2026-03-01_00:45
- [bugs] This is a genuinely interesting systems design problem. Here's how I'd think about it:
- [decisions] - Free tier covers this workload easily
- [decisions] - Protected by CF Access if you want Google auth instead of bearer token
- [decisions] | [code] | Yes | Has per-repo overrides |
- [decisions] - Stored: nothing (design proposal only, not yet a decision)

#### Session 2026-03-01_00:56
- [decisions] The right design splits by **scope, actor, and risk level**, because each operation has a different threat profile.
- [decisions] | Fetch knowledge | Leaks architectural decisions, patterns, infra hints |
- [decisions] - Even if someone discovers the URL, they can't download the hooks without your Google session
- [bugs] **Auth: Per-machine JWTs, issued at bootstrap time**
- [bugs] **How it's issued (the bootstrap flow):**
- [decisions] Because tokens are per-machine and stored in D1:
- [decisions] | Compromised | Impact | Recovery |
- [bugs] | All machine JWTs somehow | Knowledge read/write for all machines | Rotate Worker JWT secret (re-issues all tokens) |
- [decisions] If the knowledge entries are already stripped of all code and secrets by code-redactor (which they are), the **knowledge read endpoint could be public** — anyone who discovers the URL sees only abstract summaries like [string].
- [decisions] That's a judgment call based on how sensitive you consider the pattern/decision summaries.
- [decisions] - Stored: nothing (design proposal, decision pending)

## Config Worker (config.starstalk.io)
- CF Worker: deployed, zone starstalk.io, route config.starstalk.io/*
- D1 database: claude-config (c769112b-1417-462d-985b-0aeeea8f09d9)
- CF Access app: 6af45daf-fa77-471e-aaad-71b4066d8d51, policy allows theprogrammerq@gmail.com only
- Machine token: ~/.claude/swarm/.token (iMonster-WSL2, machine_id=7c43ff27-79b8-4918-8865-a0e93006deb6)
- 133 knowledge entries seeded to remote D1
- Bootstrap: bash <(curl -sL https://config.starstalk.io/bootstrap) --code <code>
- New codes: use wrangler d1 execute or POST /admin/codes (requires CF Access)

#### Session 2026-03-01_01:33
- [decisions] - Found: Prior session context covering the full design

#### Session 2026-03-01_09:59
- [bugs] The root [code] has no route — [code] is the catch-all on line 301. That's expected for the root URL.
- [bugs] The issue is the bootstrap script says:
- [bugs] - Stored: nothing (bug identified: no GET /admin route exists in config-worker, bootstrap script references it but it was never implemented)

#### Session 2026-03-01_10:08
- [decisions] - Stored: nothing (straightforward UI addition, no new architectural decisions)

#### Session 2026-03-01_10:37
- [decisions] **What's synced (D1 remote):** Abstract knowledge only — architectural decisions, bug patterns, conventions.

#### Session 2026-03-01_12:17
- [bugs] **Known bug from prior sessions:** [code] route doesn't exist in config-worker — bootstrap script referenced it but it was never implemented.

#### Session 2026-03-01_12:21
- [decisions] - Stored: nothing (operational copy, no new decisions)

#### Session 2026-03-01_12:30
- [bugs] **The problem:** In August 2023, HashiCorp changed Terraform's license from MPL (open source) to **BSL (Business Source License)** — which restricts commercial use and caused a community split.
- [decisions] - 100% HCL-compatible — same syntax, same providers, same commands ([code] instead of [code])
- [conventions] I recommended OpenTofu mainly to avoid any future licensing headaches if this setup grows.
- [conventions] If you've used Terraform before or prefer that name, we can just use Terraform — it makes zero technical difference here.
- [conventions] Same question applies to orchestration — did you want to clarify anything about the k3s vs Nomad vs Swarm choice, or do you have a preference already?
- [decisions] - Stored: nothing (explanation only, no decisions yet)

#### Session 2026-03-01_13:02
- [decisions] - [code] — Ubuntu 24.04 cloud image download (once, [code])
- [decisions] - [code] — k3sup install + join loop over [code], auto-reads IPs from Terraform outputs
