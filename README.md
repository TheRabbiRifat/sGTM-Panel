# Hostaffin sGTM Hosting Platform

[![CI — Control Plane](https://img.shields.io/badge/CI-control--plane-blue)](#)
[![CI — Admin Panel](https://img.shields.io/badge/CI-admin--panel-blue)](#)
[![CI — WHMCS Module](https://img.shields.io/badge/CI-whmcs--module-blue)](#)
[![OS](https://img.shields.io/badge/OS-YUM%20family-important)](#)
[![License](https://img.shields.io/badge/license-Proprietary-red)](#)

A WHMCS-native, fully managed **Server-side Google Tag Manager (sGTM)** hosting
product. Customers buy and manage sGTM containers entirely from WHMCS; the
platform automates provisioning, lifecycle, SSL, metering, custom loaders,
cookie extensions, bot detection, ad-block recovery, and billing.

```
┌──────────┐    ┌────────────────┐    ┌──────────────┐    ┌──────────────────────┐
│  WHMCS   │───▶│ Control Plane  │───▶│  Node Agent  │───▶│ Docker Swarm (sGTM)  │
│  (PHP)   │    │   (Go/Fiber)   │    │  (per node)  │    │  Traefik (edge TLS)  │
└──────────┘    └────────────────┘    └──────────────┘    └──────────────────────┘
                       │
                       ▼
            ┌────────────────────┐
            │ Postgres · Redis   │
            │ ClickHouse (stats) │
            └────────────────────┘
```

---

## Table of contents

- [Features](#features)
- [Repository layout](#repository-layout)
- [Quick start — local dev](#quick-start--local-dev)
- [Production install — YUM-family distros](#production-install--yum-family-distros)
- [Uninstall](#uninstall)
- [Components](#components)
- [WHMCS module](#whmcs-module)
- [Custom Loader & Cookie Extension](#custom-loader--cookie-extension)
- [Admin Move Service](#admin-move-service)
- [API reference](#api-reference)
- [Operations](#operations)
- [Tech stack](#tech-stack)
- [Documentation](#documentation)
- [CI / CD](#ci--cd)
- [License](#license)

---

## Features

- **WHMCS-native provisioning** — purchase, suspend, unsuspend, terminate, and
  change-package flows are all wired to the WHMCS module.
- **WHMCS client-area self-service** — customers add custom domains, manage
  custom loaders (alias + FBP/FBC + trigger + DNT), toggle cookie lifetime
  extensions, view request counts, and restart their container — all without
  raising a support ticket.
- **Multi-tenant Docker Swarm** — one container per customer, scheduled across
  master nodes with a `hostaffin_role=master` label.
- **Traefik v3 reverse proxy** with automatic Let's Encrypt certificates via
  HTTP-01 ACME challenges.
- **JWT (RS256) auth + Argon2id password hashing** with role-based access
  control (`super_admin`, `admin`, `support`).
- **Custom Loader** — first-party gated JS snippet with **renameable JS alias**
  (`gtm.js`, `gtag.js`, `analytics.js`, `trk.js`, `trk-ss.js`, `fbevents.js`,
  `pixel.js`, `loader.js`, `custom`), **FBP / FBC Facebook-cookie forwarding**,
  vendor-mapping JSON, and SRI hash. ([details](#custom-loader--cookie-extension))
- **Cookie Extension** — extend third-party cookie lifetime (clamped to
  Chrome's 395-day cap) with vendor compatibility matrix. ([details](#custom-loader--cookie-extension))
- **Admin-only Move Service** — transfer a container from one master node to
  another (WHM-style `Transfer Account`), single or bulk, with safety
  confirmation. ([details](#admin-move-service))
- **Bot detection** — UA regex gating baked into the loader plus server-side
  inspection at `LoaderRun`.
- **Ad-block recovery** — first-party cookie on customer domain via
  `cookie_extensions` plus a probe-and-fallback JS path for blocked
  `gtm.js` requests.
- **Usage metering** — daily rollups in PostgreSQL, raw events in ClickHouse
  with a `events_raw` → `events_5m` materialized view.
- **Asynq worker** for background jobs: provisioning, restarts, upgrades,
  domain verification, SSL checks, quota scans, usage rollups.
- **Admin Panel** (Next.js 14 + Shadcn UI) with dashboard, services, nodes,
  plans, users, and audit log.
- **Comprehensive runbooks** for adding nodes, failover, JWT key rotation,
  and disaster recovery.

---

## Repository layout

```
sGTM-Panel/
├── README.md                              # this file
├── HOSTAFFIN_SGTM_PLATFORM_PLAN.md        # full PRD + architecture
├── BUILD_SUMMARY.md                       # what was scaffolded
├── Makefile                               # convenience targets
├── docker-compose.yml                     # local dev stack
├── .env.example                           # env template
│
├── control-plane/                         # Go + Fiber backend (source of truth)
│   ├── cmd/{api,worker,migrate,seed}/     # 4 binaries
│   ├── internal/
│   │   ├── auth/         # JWT (RS256) + Argon2id
│   │   ├── config/
│   │   ├── db/           # pgx + sqlx
│   │   ├── domain/       # models
│   │   ├── handlers/     # Fiber routes + public loaders
│   │   ├── observability/
│   │   ├── queue/        # Asynq
│   │   ├── redis/
│   │   ├── repos/        # 9 repos
│   │   └── services/     # 4 service packages (provisioning, loaders, …)
│   ├── migrations/       # 5 SQL files + ClickHouse DDL
│   ├── Dockerfile
│   └── README.md
│
├── node-agent/                            # Go daemon (one per Swarm node)
│   ├── cmd/agent/
│   ├── internal/{commands,config,heartbeat,metrics}/
│   ├── Dockerfile
│   └── README.md
│
├── admin-panel/                           # Next.js 14 + Shadcn
│   ├── app/(dashboard)/                   # dashboard, services, nodes, plans, …
│   ├── components/{ui,features,sidebar}/
│   ├── lib/{api,utils}.ts
│   ├── Dockerfile
│   └── README.md
│
├── whmcs-module/                          # WHMCS PHP module
│   └── modules/servers/hostaffin_sgtm/
│       ├── hostaffin_sgtm.php
│       ├── callback.php                   # HMAC-signed webhook receiver
│       ├── lib/{ApiClient,Hooks}.php      # block-aware template engine
│       └── templates/clientarea.tpl       # full client-area UI
│
├── traefik/                               # Reverse proxy
│   ├── traefik.yml
│   ├── docker-compose.yml
│   └── sample-sgtm-stack.yml              # example sGTM service labels
│
├── infra/                                 # Ops
│   ├── ansible/{playbook,roles}/          # docker, traefik, node-agent
│   ├── systemd/hostaffin-node-agent.service
│   └── scripts/
│       ├── installer.sh                   # one unified installer (install / uninstall / interactive / health-check)
│       ├── bootstrap-node.sh              # quick local dev bootstrap
│       ├── rotate-jwt.sh                  # rotate JWT keypair
│       └── backup.sh                      # nightly Postgres → S3 backup
│
├── docs/
│   ├── api.md                             # REST API reference
│   ├── runbooks/{add-node,failover}.md
│   └── decisions/0001-swarm-over-k8s.md   # ADR
│
└── .github/workflows/                     # CI
    ├── ci-control-plane.yml
    ├── ci-admin-panel.yml
    └── ci-whmcs-module.yml
```

---

## Quick start — local dev

> Requires **Docker 24+**, **Go 1.22+**, **Node 20+**, and **Make**.

```bash
# 1. Clone
git clone https://github.com/TheRabbiRifat/sGTM-Panel.git
cd sGTM-Panel

# 2. Environment
cp .env.example .env
# Edit .env if needed (defaults work for local dev)

# 3. Start dependencies
make up                       # postgres + redis + clickhouse + traefik

# 4. Migrate + seed
make migrate                  # runs control-plane/cmd/migrate up
make seed                     # creates 3 plans + super_admin
                              # → admin@hostaffin.local / ChangeMe!123

# 5. Run the control plane
make run-api                  # API on :8080
make run-worker               # in another terminal
make run-admin                # admin panel on :3000 (in another terminal)
```

Default super-admin: **`admin@hostaffin.local` / `ChangeMe!123`**
(change it after first login via the admin panel).

**Useful endpoints**

| URL                              | Purpose                  |
| -------------------------------- | ------------------------ |
| http://localhost:8080/healthz    | control plane health     |
| http://localhost:3000            | admin panel (Next.js)    |
| http://localhost:8081            | Traefik dashboard        |
| http://localhost:8123/play       | ClickHouse playground    |
| http://localhost:5050            | pgAdmin (if enabled)     |

---

## Production install — YUM-family distros

The repo ships with a fully-tested, non-interactive installer that targets
**any YUM-family distro** — AlmaLinux / Rocky / RHEL / CentOS Stream /
Oracle Linux / Fedora / Amazon Linux. Package-manager detection is
automatic (`dnf` on modern, `yum` on legacy); force a specific one with
`HOSTAFFIN_PM=dnf|yum` if needed. The installer handles **everything**:
packages, firewall, SELinux, Docker, Swarm, Traefik, node-agent, control
plane, PostgreSQL, Redis, ClickHouse, migrations, and seed.

### Supported distros

| Distro                  | Versions                | Package manager          |
| ----------------------- | ----------------------- | ------------------------ |
| AlmaLinux               | 8, 9                    | dnf                      |
| Rocky Linux             | 8, 9                    | dnf                      |
| RHEL                    | 7, 8, 9                 | yum (7) / dnf (8+)       |
| CentOS Stream           | 8, 9                    | dnf                      |
| Oracle Linux            | 7, 8, 9                 | yum (7) / dnf (8+)       |
| Fedora                  | 36+                     | dnf                      |
| Amazon Linux            | 2, 2023                 | yum (AL2) / dnf (AL2023) |

### One-liner (recommended)

The recommended install uses a token-safe wrapper
([`one-liner-install.sh`](./infra/scripts/one-liner-install.sh)) that
downloads the installer + shared libs to a private temp dir, verifies
their SHA-256 against an embedded manifest, runs the installer with
your secrets loaded from a `0600` env-file, and `shred`s the temp dir
on exit.

> **Why not `curl … | sudo bash`?** Tokens passed on the command line
> show up in `ps` / `/proc/<pid>/cmdline` and shell history. The wrapper
> refuses to run without `--env-file`, and only `HOSTAFFIN_*` variables
> from that file are allowed through.

#### 1. Stage secrets (mode `0600`, owner `root`)

```bash
sudo install -m 0600 /dev/null /etc/hostaffin/install.env
sudo vi /etc/hostaffin/install.env
```

```ini
# /etc/hostaffin/install.env
HOSTAFFIN_MODE=local
# HOSTAFFIN_JOIN_TOKEN=SWMTKN-1-...
# HOSTAFFIN_MANAGER_ADDR=10.0.0.5:2377
# HOSTAFFIN_CONTROL_PLANE_URL=https://cp.example.com
# HOSTAFFIN_NODE_ID=master-fra-01
# HOSTAFFIN_NODE_API_KEY=replace-me
HOSTAFFIN_GITHUB_TOKEN=ghp_replace_me
```

The wrapper only passes `HOSTAFFIN_[A-Z0-9_]+` variables through, so
typos or stray exports won't leak into the installer.

#### 2. Run the wrapper

```bash
sudo bash -c '
  tmp=$(mktemp -d) &&
  curl -fsSL --proto =https \
    https://raw.githubusercontent.com/TheRabbiRifat/sGTM-Panel/main/infra/scripts/one-liner-install.sh \
    -o "$tmp/wrap" &&
  bash "$tmp/wrap" --env-file /etc/hostaffin/install.env --yes &&
  rm -rf "$tmp"
'
```

This installs the **local all-in-one** profile (single host, single
swarm manager) — perfect for a production start or a staging env.

#### Alternative: pipe the wrapper into bash directly

If you really want a single line, you can pipe the wrapper itself into
bash (it is small and does not need tokens to run — only the child
installer does):

```bash
curl -fsSL --proto =https \
  https://raw.githubusercontent.com/TheRabbiRifat/sGTM-Panel/main/infra/scripts/one-liner-install.sh \
  | sudo bash -s -- --env-file /etc/hostaffin/install.env --yes
```

### Interactive wizard (recommended for first-time installs)

```bash
sudo ./infra/scripts/install-interactive.sh
```

The wizard is a guided, full-screen TUI with an ASCII banner that walks
you through every important decision:

1. **Timezone** — used for logs, scheduled jobs, ACME windows
2. **Public DNS wildcard hostname** — e.g. `edge.hostaffin.com`
3. **Install mode** — `local`, `master`, or `controlplane`
4. **Swarm join details** *(master mode only)* — manager address + token
5. **Admin account** — email + password (or auto-generate)
6. **GHCR token** *(optional)* — pull prebuilt images
7. **Advanced** — firewall / swap / node ID
8. **Review** — confirm before anything is installed

Each step has a progress bar; long-running commands show a spinner.
You can save your answers with `--save-config answers.env` and re-run
unattended with `--config answers.env --non-interactive`.

### Modes

| Mode          | Use case                                  | What gets installed                              |
| ------------- | ----------------------------------------- | ------------------------------------------------ |
| `local`       | all-in-one single host (default)          | everything: DB, control plane, traefik, agent     |
| `master`      | join an existing swarm as a master node   | docker + traefik + node-agent only               |
| `controlplane`| control plane + DB stack only             | docker, postgres/redis/clickhouse, control plane  |

> Every node in the cluster is a **master** node — there is no separate
> "edge" or "slave" role. Any node can run Traefik and serve customer
> containers.

### Provision a fleet

**First host (becomes Swarm manager + control plane):**

```bash
# Secrets file just needs HOSTAFFIN_MODE + HOSTAFFIN_GITHUB_TOKEN
echo 'HOSTAFFIN_MODE=local'        | sudo tee /etc/hostaffin/install.env
echo 'HOSTAFFIN_GITHUB_TOKEN=ghp…'  | sudo tee -a /etc/hostaffin/install.env
sudo chmod 0600 /etc/hostaffin/install.env

sudo bash -c '
  tmp=$(mktemp -d) &&
  curl -fsSL --proto =https \
    https://raw.githubusercontent.com/TheRabbiRifat/sGTM-Panel/main/infra/scripts/one-liner-install.sh \
    -o "$tmp/wrap" &&
  bash "$tmp/wrap" --env-file /etc/hostaffin/install.env --yes
'
# → saves join token + manager IP; copy them.
```

**Each additional master node:**

```bash
sudo tee /etc/hostaffin/install.env >/dev/null <<'EOF'
HOSTAFFIN_MODE=master
HOSTAFFIN_JOIN_TOKEN=SWMTKN-1-...
HOSTAFFIN_MANAGER_ADDR=10.0.0.5:2377
HOSTAFFIN_CONTROL_PLANE_URL=https://cp.example.com
HOSTAFFIN_NODE_ID=master-fra-02
HOSTAFFIN_NODE_API_KEY=replace-me
HOSTAFFIN_GITHUB_TOKEN=ghp_...
EOF
sudo chmod 0600 /etc/hostaffin/install.env

sudo bash -c '
  tmp=$(mktemp -d) &&
  curl -fsSL --proto =https \
    https://raw.githubusercontent.com/TheRabbiRifat/sGTM-Panel/main/infra/scripts/one-liner-install.sh \
    -o "$tmp/wrap" &&
  bash "$tmp/wrap" --env-file /etc/hostaffin/install.env --yes
'
```

> There is no separate `--mode worker` anymore — every node is a master.

### Calling the installer directly (no wrapper)

If you've already cloned the repo and don't need the wrapper, you can
call the canonical installer directly. **Never put tokens on the
command line** — export them from the same env-file instead:

```bash
# Load secrets into the current shell, then run the installer.
set -a; source /etc/hostaffin/install.env; set +a
sudo -E ./infra/scripts/install-yum.sh --mode local --non-interactive
```

The installer's `BASH_SOURCE[0]` resolves correctly here because the
script is on disk (not piped via stdin), so the `lib-pm.sh` /
`lib-ui.sh` sources work without any fallback.

### Wrapper flags

| Flag                     | Description                                                                       |
| ------------------------ | --------------------------------------------------------------------------------- |
| `--env-file PATH`        | path to a `0600` env-file containing `HOSTAFFIN_*` variables (required)            |
| `--repo-base URL`        | override the GitHub raw URL (default: `main` of `TheRabbiRifat/sGTM-Panel`)       |
| `-y`, `--yes`, `--assume-yes` | pass `--non-interactive` through to the installer                           |

### Wrapper guarantees

- **Tokens never touch the command line.** The wrapper refuses to run
  unless `--env-file` points at a file whose mode is `0400` or `0600`.
  Only `HOSTAFFIN_[A-Z0-9_]+` variables from that file are passed
  through — anything else aborts.
- **Tokens are exported `readonly`** to the child installer process and
  `unset` from the wrapper's environment after the child exits.
- **Checksum verification.** Every fetched script
  (`install-yum.sh`, `lib-pm.sh`, `lib-ui.sh`) is verified against an
  embedded SHA-256 manifest before execution. The pins are
  auto-bumped by the [`installer-pins`](./.github/workflows/ci-installer-pins.yml)
  CI workflow whenever any of those scripts change on `main`.
- **No leftovers.** The wrapper's working dir (`mktemp -d`, mode `0700`)
  is wiped with `shred -u` + `rm -rf` on `EXIT` / `INT` / `TERM`.

### Useful installer flags

| Flag                      | Description                                                |
| ------------------------- | ---------------------------------------------------------- |
| `--mode {local,master,controlplane}` | install profile (default: `local`)            |
| `--join-token TOKEN`      | swarm worker join token (required for `master`)   |
| `--manager-addr ADDR`     | `<ip>:2377` of an existing manager                        |
| `--control-plane-url URL` | public URL of the control plane (for the node-agent)       |
| `--node-id ID`            | override the auto-generated `master-<host>-01` ID          |
| `--node-api-key KEY`      | pre-shared HMAC key with the control plane                 |
| `--github-token TOKEN`    | GHCR PAT for pulling pre-built images                      |
| `--project-dir DIR`       | override `/opt/hostaffin`                                  |
| `--non-interactive`       | skip all confirmation prompts                              |
| `--skip-firewall`         | do not modify firewalld                                    |
| `--skip-swap-disable`     | keep swap enabled                                          |

All flags also accept `HOSTAFFIN_<UPPER_SNAKE_CASE>` env-var overrides.
`HOSTAFFIN_PM=dnf|yum` forces a specific package manager (skip the
auto-detect).

### What the installer does

- Auto-detects dnf vs yum (via `infra/scripts/lib-pm.sh`)
- Updates the system and enables EPEL
- Installs Docker Engine 26.1.3 + Compose plugin
- Tunes kernel (`/etc/sysctl.d/99-hostaffin.conf`) and ulimits
- Configures **firewalld** (ports 80, 443, 2377, 7946, 4789, 8080, 3000,
  9100, 8123, 9000)
- Adjusts **SELinux** (custom `hostaffin` policy module for Traefik)
- Initializes or joins a **Docker Swarm**
- Labels the node with `hostaffin_role=master`
- Creates the `hostaffin_edge` overlay network
- Installs **Traefik v3** as a systemd-managed, host-networked container
- Installs the **node-agent** as a systemd service
- Builds (or pulls) the **control-plane** and **admin-panel** Docker images
- Brings up **PostgreSQL 16**, **Redis 7**, **ClickHouse 24** via compose
- Generates a fresh **JWT RSA-2048 keypair**
- Generates a strong **admin password** and writes it to
  `/root/.hostaffin-admin-password` (chmod 0600)
- Runs **migrations** + **seed** (3 plans + super admin)
- Performs **health checks** and prints a final summary

See [`infra/scripts/install-yum.sh`](./infra/scripts/install-yum.sh)
for full reference (the wrapper just downloads and runs it). Both
scripts are **shellcheck-clean** (`shellcheck --shell=bash` → exit 0).

---

## Uninstall

A companion uninstaller reverses every artifact of the installer. By default
it stops services and removes containers, but keeps config and data — pass
`--purge` to also remove `/opt/hostaffin`, `/etc/hostaffin`, the admin
password file, ACME data, and log directories.

```bash
# Stop services + remove containers, keep data
sudo ./infra/scripts/uninstall-yum.sh --mode local

# Full purge (irreversible)
sudo ./infra/scripts/uninstall-yum.sh --mode local --purge

# Dry-ish: stop everything but stay in the swarm and keep Docker
sudo ./infra/scripts/uninstall-yum.sh \
  --mode local --purge --leave-swarm --keep-docker --non-interactive
```

---

## Components

### 1. Control Plane (`control-plane/`)

The Go + Fiber backend. Owns the source of truth (PostgreSQL), dispatches
work to node-agents via Asynq (Redis), and serves:

- **Admin API** (JWT-protected) — services, plans, nodes, users, audit
- **Public API** (rate-limited) — `/loader.js`, `/loader.js/run`,
  `/cookie/extend/:name`
- **Webhook** — receives HMAC-signed events from WHMCS

Four binaries: `cmd/api`, `cmd/worker`, `cmd/migrate`, `cmd/seed`. See
[`control-plane/README.md`](./control-plane/README.md).

### 2. Node Agent (`node-agent/`)

A small Go daemon that runs on every Swarm node. It:

- Posts **heartbeats** + **metrics** to the control plane
- Receives **commands** (deploy / restart / delete) and executes them via
  the local Docker socket
- Applies CPU / memory limits from the plan

See [`node-agent/README.md`](./node-agent/README.md).

### 3. Admin Panel (`admin-panel/`)

Next.js 14 App Router with Shadcn UI. Server-side fetchers rewrite `/api/cp/*`
to the control plane.

Pages: Dashboard, Services (list + detail with Overview/Loaders/Cookie
Extensions/Metrics tabs), **Services → Move** (admin-only bulk transfer),
Nodes, Plans, Users, Audit, Settings, Login.

See [`admin-panel/README.md`](./admin-panel/README.md).

---

## WHMCS module

Drop the contents of `whmcs-module/modules/servers/hostaffin_sgtm/` into your
WHMCS installation's `modules/servers/` directory and create a new server of
type **Hostaffin sGTM** in WHMCS.

The module implements:

- `CreateAccount` / `SuspendAccount` / `UnsuspendAccount` /
  `TerminateAccount` / `ChangePackage`
- `ClientAreaCustomButtonArray` / `ClientAreaOutput` (client area panel)
- `AdminCustomButtonArray` (admin actions)
- HMAC-signed webhook receiver at `callback.php`
- Auto-created custom fields: `service_id`, `edge_hostname`, `plan_slug`
- **Client-area self-service UI** for custom domains, custom loaders, cookie
  lifetime extensions, request counts, and restart

### What customers can do from the client area

| Feature                       | What they can do                                                                                  |
| ----------------------------- | ------------------------------------------------------------------------------------------------- |
| Service status + plan         | View status, plan, container URL                                                                  |
| Usage / request count         | Monthly request count, loader hits, cookie-ext hits, bandwidth                                    |
| Custom domain                 | Add → receive CNAME / TXT instructions → re-verify DNS → ACME cert issued                        |
| Custom loader                 | Pick JS alias (`gtm.js`, `gtag.js`, `trk.js`, `trk-ss.js`, `analytics.js`, `fbevents.js`, `pixel.js`, `loader.js`, `custom`), set trigger (immediate / delay / consent cookie / on element), map `_fbp` / `_fbc` Facebook cookies, honor DNT, pause / resume, rotate |
| Cookie lifetime extension     | Add (cookie name + vendor URL + lifetime ≤ 395 days), pause / resume, delete                      |
| Restart container             | One-click restart                                                                                 |

The client-area UI is rendered by a **custom block-aware template engine**
in `lib/Hooks.php` that supports `{{if}}` / `{{range}}` (nested),
`{{.field}}`, pipes (`|default:X`, `|raw`, `|upper`, `|lower`), and
`{{partial name}}`. Every state-changing form is protected by the standard
WHMCS CSRF token.

Set the **API URL** and **API Key** in the WHMCS module config (they must
match the control plane's `CONTROL_PLANE_URL` and a server token).

---

## Custom Loader & Cookie Extension

Two WHMCS-billable add-on features implemented as first-class tables in the
control plane.

### Custom Loader

A first-party, gated JavaScript snippet served from the customer's own edge
hostname.

- **Loader ID format:** `lk_xxxxxxxx` (8 bytes hex, e.g. `lk_3f9a2c1b`)
- **JS file alias:** `gtm.js`, `gtag.js`, `analytics.js`, `trk.js`,
  `trk-ss.js`, `fbevents.js`, `pixel.js`, `loader.js`, or `custom` —
  the served URL is renamed to evade ad-blockers and basic blocklists.
- **FBP / FBC forwarding:** the loader reads `_fbp` / `_fbc` cookies
  from the page and forwards them into the `/loader.js/run` URL so the
  server can dedupe and report on Facebook-click attribution.
- **Gating modes:** `immediate`, `consent`, `delay`, `element`
- **SRI hash** computed server-side; snippet copy includes the correct
  `<script integrity=…>` tag
- **Rotation grace period:** previous loader keeps serving for 24h after
  regeneration; both `lk_…` IDs valid in parallel
- **Per-service rate limit:** 60 req/min per IP (Redis token bucket)
- **Bot detection:** UA regex (`/bot|crawl|spider/i`) gate is baked into
  the rendered JS, configurable per-loader via `allow_bots`.

### Cookie Extension

Extend the lifetime of third-party cookies set by vendor tags.

- **Lifetime cap:** clamped to **395 days** (Chrome's max) at both DB
  (`CHECK` constraint) and service layer
- **Vendor compatibility matrix:** a JSON config of vendor URL → extension
  behavior
- **Logs:** IP-hashed (HMAC-SHA256), no raw IPs ever written
- **Purge job:** runs daily, removes `cookie_extension_logs` older than 90 days
- **Per-vendor rate limit:** 30 req/min per IP
- **Ad-block recovery:** because the cookie is set on the customer's own
  first-party domain, ad-blockers see it as legitimate and allow it
  through, recovering most third-party-cookie breakage caused by ITP.

See the full plan in [§15A & §15B of `HOSTAFFIN_SGTM_PLATFORM_PLAN.md`](./HOSTAFFIN_SGTM_PLATFORM_PLAN.md).

---

## Admin Move Service

WHM-style **Transfer Account** tool for operators — relocate an sGTM
container from one master node to another. Admin-only.

### Single-service move

On any `/services/:id` page, click **Move to another node**:

1. The dialog shows the service's current node (with CPU / RAM / container count).
2. Pick an online master node from the candidate list.
3. (Recommended) click **Drain** on the destination node first so no new
   containers land on it during the transfer.
4. Type the service's edge hostname to confirm — typo-proof safety check
   borrowed from WHM.
5. The container is re-pulled on the destination, redeployed with the same
   plan / loader / cookie / domain settings, and `services.node_id` is
   updated. Traefik re-discovers the route via Docker labels (no DNS change).

Tracking on the service pauses for ~30–90 s during the move.

### Bulk move

`/services/move` lets you relocate every active service currently on a
*different* node in one go. The page issues one `POST /api/services/:id/move`
per affected service in parallel and reports per-service success / failure
in a collapsible details block.

### API

| Verb   | Path                          | Purpose                                    |
| ------ | ----------------------------- | ------------------------------------------ |
| `POST` | `/api/services/:id/move`      | Move a single service to another master    |
| `POST` | `/api/nodes/:id/drain`        | Stop new containers landing on a master    |

Full admin-panel documentation lives in [`admin-panel/README.md`](./admin-panel/README.md#move-service-admin-only).

---

## API reference

See [`docs/api.md`](./docs/api.md) for the full REST surface. Highlights:

| Method | Path                                | Auth   | Description                       |
| ------ | ----------------------------------- | ------ | --------------------------------- |
| POST   | `/api/v1/auth/login`                | —      | obtain JWT                        |
| GET    | `/api/v1/services`                  | admin  | list services                     |
| POST   | `/api/v1/services`                  | admin  | provision new service             |
| POST   | `/api/v1/services/:id/restart`      | admin  | restart container                 |
| POST   | `/api/v1/services/:id/suspend`      | admin  | suspend                           |
| POST   | `/api/v1/services/:id/unsuspend`    | admin  | unsuspend                         |
| POST   | `/api/v1/services/:id/terminate`    | admin  | terminate                         |
| POST   | `/api/v1/services/:id/move`         | admin  | move container to another master  |
| POST   | `/api/v1/services/:id/loaders`      | admin  | create custom loader              |
| PATCH  | `/api/v1/services/:id/loaders/:lid` | admin  | update loader config (alias, FBP/FBC, trigger, DNT, …) |
| POST   | `/api/v1/services/:id/loaders/:lid/regenerate` | admin | rotate loader ID     |
| POST   | `/api/v1/services/:id/loaders/:lid/enable`   | admin | resume loader       |
| POST   | `/api/v1/services/:id/loaders/:lid/disable`  | admin | pause loader        |
| POST   | `/api/v1/services/:id/cookie-extensions`     | admin | add cookie extension    |
| PATCH  | `/api/v1/cookie-extensions/:id`     | admin  | toggle / update extension         |
| DELETE | `/api/v1/cookie-extensions/:id`     | admin  | remove extension                  |
| POST   | `/api/v1/services/:id/domains`      | admin  | add custom domain                 |
| POST   | `/api/v1/domains/:id/verify`        | admin  | re-check DNS                      |
| DELETE | `/api/v1/domains/:id`               | admin  | remove custom domain              |
| POST   | `/api/v1/nodes/:id/drain`           | admin  | stop new containers landing       |
| GET    | `/loader.js?lid=…`                  | public | serve gated loader                |
| GET    | `/loader.js/run?lid=…`              | public | tracking pixel + bot inspection   |
| GET    | `/cookie/extend/:name?v=…&t=…&rt=…` | public | set the extended cookie           |
| POST   | `/webhooks/whmcs`                   | HMAC   | WHMCS event receiver              |
| GET    | `/healthz`                          | —      | liveness                          |

---

## Operations

- **Add a master node** → [`docs/runbooks/add-node.md`](./docs/runbooks/add-node.md)
- **Failover** → [`docs/runbooks/failover.md`](./docs/runbooks/failover.md)
- **Interactive install** → `sudo ./infra/scripts/install-interactive.sh`
- **Unattended re-install** → `sudo ./infra/scripts/install-interactive.sh --config answers.env --non-interactive`
- **Rotate JWT keys** → `sudo ./infra/scripts/rotate-jwt.sh`
- **Backup** → `sudo ./infra/scripts/backup.sh` (postgres → S3)
- **ADR-0001: why Docker Swarm, not Kubernetes** →
  [`docs/decisions/0001-swarm-over-k8s.md`](./docs/decisions/0001-swarm-over-k8s.md)

---

## Tech stack

| Layer              | Tech                                                   |
| ------------------ | ------------------------------------------------------ |
| Backend            | Go 1.22 + [Fiber v2](https://gofiber.io)               |
| Database           | PostgreSQL 16 (pgx + sqlx)                             |
| Cache / queue      | Redis 7 + [Asynq](https://github.com/hibiken/asynq)    |
| Analytics          | ClickHouse 24                                          |
| Auth               | JWT (RS256) + Argon2id                                 |
| Frontend           | Next.js 14 App Router + Shadcn UI + TanStack Query     |
| WHMCS integration  | PHP 8.1+ (cURL + HMAC-SHA256)                          |
| Orchestration      | Docker Swarm                                           |
| Reverse proxy      | Traefik v3 (Let's Encrypt ACME HTTP-01)                |
| Provisioning       | Custom bash installer (any YUM-family distro) + Ansible roles  |
| Supported OS       | AlmaLinux 8/9, Rocky 8/9, RHEL 7/8/9, CentOS Stream, Oracle, Fedora, Amazon Linux |
| CI                 | GitHub Actions (Go test+build, Next.js build, PHP linter) |

---

## Documentation

- [Full PRD + plan](./HOSTAFFIN_SGTM_PLATFORM_PLAN.md) — 27 sections + Custom
  Loader & Cookie Extension addenda
- [Build summary](./BUILD_SUMMARY.md) — what was scaffolded for v1
- [API reference](./docs/api.md)
- [Runbooks](./docs/runbooks/)
- [Decisions (ADRs)](./docs/decisions/)

---

## CI / CD

GitHub Actions workflows in `.github/workflows/`:

- `ci-control-plane.yml` — Go test + build for the API & worker
- `ci-admin-panel.yml` — typecheck, lint, build for the Next.js admin panel
- `ci-whmcs-module.yml` — PHP syntax check for the WHMCS module

---

## License

Proprietary — © Hostaffin Ltd. All rights reserved.

Unauthorized copying, redistribution, or reverse engineering is prohibited.
