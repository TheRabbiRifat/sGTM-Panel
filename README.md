# Hostaffin sGTM Hosting Platform

[![CI — Control Plane](https://img.shields.io/badge/CI-control--plane-blue)](#)
[![CI — Admin Panel](https://img.shields.io/badge/CI-admin--panel-blue)](#)
[![CI — WHMCS Module](https://img.shields.io/badge/CI-whmcs--module-blue)](#)
[![OS](https://img.shields.io/badge/OS-Alma%20Linux%209-important)](#)
[![License](https://img.shields.io/badge/license-Proprietary-red)](#)

A WHMCS-native, fully managed **Server-side Google Tag Manager (sGTM)** hosting
product. Customers buy and manage sGTM containers entirely from WHMCS; the
platform automates provisioning, lifecycle, SSL, metering, custom loaders,
cookie extensions, and billing.

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
- [Production install — Alma Linux 9](#production-install--alma-linux-9)
- [Uninstall](#uninstall)
- [Components](#components)
- [WHMCS module](#whmcs-module)
- [Custom Loader & Cookie Extension](#custom-loader--cookie-extension)
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
- **Multi-tenant Docker Swarm** — one container per customer, scheduled across
  edge nodes with a `hostaffin_role=edge` label.
- **Traefik v3 reverse proxy** with automatic Let's Encrypt certificates via
  HTTP-01 ACME challenges.
- **JWT (RS256) auth + Argon2id password hashing** with role-based access
  control (`super_admin`, `admin`, `support`).
- **Custom Loader** — first-party gated JS snippet with SRI hash and rotation
  grace period. ([details](#custom-loader--cookie-extension))
- **Cookie Extension** — extend third-party cookie lifetime (clamped to
  Chrome's 395-day cap) with vendor compatibility matrix. ([details](#custom-loader--cookie-extension))
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
│   ├── migrations/       # 4 SQL files + ClickHouse DDL
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
│       ├── lib/{ApiClient,Hooks}.php
│       └── templates/clientarea.tpl
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
│       ├── install-almalinux9.sh          # production installer
│       ├── uninstall-almalinux9.sh        # production uninstaller
│       ├── bootstrap-node.sh
│       ├── rotate-jwt.sh
│       └── backup.sh
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

## Production install — Alma Linux 9

The repo ships with a fully-tested, non-interactive installer for fresh Alma
Linux 9 / Rocky 9 / RHEL 9 hosts. It handles **everything**: packages,
firewall, SELinux, Docker, Swarm, Traefik, node-agent, control plane,
PostgreSQL, Redis, ClickHouse, migrations, and seed.

### One-liner (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/TheRabbiRifat/sGTM-Panel/main/infra/scripts/install-almalinux9.sh \
  | sudo bash -s -- --mode local --non-interactive
```

This installs the **local all-in-one** profile (single host, single swarm
manager) — perfect for production start or for setting up a staging env.

### Modes

| Mode          | Use case                                  | What gets installed                              |
| ------------- | ----------------------------------------- | ------------------------------------------------ |
| `local`       | all-in-one single host (default)          | everything: DB, control plane, traefik, agent     |
| `edge`        | join an existing swarm as an edge node    | docker + traefik + node-agent only               |
| `worker`      | join an existing swarm as a worker        | docker + node-agent only                         |
| `controlplane`| control plane + DB stack only             | docker, postgres/redis/clickhouse, control plane  |

### Provision a fleet

```bash
# 1. On the FIRST host (becomes the Swarm manager + control plane)
sudo ./infra/scripts/install-almalinux9.sh \
  --mode local --non-interactive
# → saves join token + manager IP; copy them.

# 2. On each additional edge node
sudo ./infra/scripts/install-almalinux9.sh \
  --mode edge \
  --join-token <WORKER-TOKEN> \
  --manager-addr <MANAGER-IP>:2377 \
  --non-interactive

# 3. On each additional worker node
sudo ./infra/scripts/install-almalinux9.sh \
  --mode worker \
  --join-token <WORKER-TOKEN> \
  --manager-addr <MANAGER-IP>:2377 \
  --non-interactive
```

### Useful flags

| Flag                      | Description                                                |
| ------------------------- | ---------------------------------------------------------- |
| `--mode {local,edge,worker,controlplane}` | install profile (default: `local`)            |
| `--join-token TOKEN`      | swarm worker join token (required for `edge` / `worker`)   |
| `--manager-addr ADDR`     | `<ip>:2377` of an existing manager                        |
| `--control-plane-url URL` | public URL of the control plane (for the node-agent)       |
| `--node-id ID`            | override the auto-generated `edge-<host>-01` ID            |
| `--node-api-key KEY`      | pre-shared HMAC key with the control plane                 |
| `--github-token TOKEN`    | GHCR PAT for pulling pre-built images                      |
| `--project-dir DIR`       | override `/opt/hostaffin`                                  |
| `--non-interactive`       | skip all confirmation prompts                              |
| `--skip-firewall`         | do not modify firewalld                                    |
| `--skip-swap-disable`     | keep swap enabled                                          |

All flags also accept `HOSTAFFIN_<UPPER_SNAKE_CASE>` env-var overrides.

### What the installer does

- Updates the system and enables EPEL
- Installs Docker Engine 26.1.3 + Compose plugin
- Tunes kernel (`/etc/sysctl.d/99-hostaffin.conf`) and ulimits
- Configures **firewalld** (ports 80, 443, 2377, 7946, 4789, 8080, 3000,
  9100, 8123, 9000)
- Adjusts **SELinux** (custom `hostaffin` policy module for Traefik)
- Initializes or joins a **Docker Swarm**
- Labels the node with `hostaffin_role=edge`
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

See [`infra/scripts/install-almalinux9.sh`](./infra/scripts/install-almalinux9.sh)
for full reference. The script is **shellcheck-clean** (`shellcheck --shell=bash` → exit 0).

---

## Uninstall

A companion uninstaller reverses every artifact of the installer. By default
it stops services and removes containers, but keeps config and data — pass
`--purge` to also remove `/opt/hostaffin`, `/etc/hostaffin`, the admin
password file, ACME data, and log directories.

```bash
# Stop services + remove containers, keep data
sudo ./infra/scripts/uninstall-almalinux9.sh --mode local

# Full purge (irreversible)
sudo ./infra/scripts/uninstall-almalinux9.sh --mode local --purge

# Dry-ish: stop everything but stay in the swarm and keep Docker
sudo ./infra/scripts/uninstall-almalinux9.sh \
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
Extensions/Metrics tabs), Nodes, Plans, Users, Audit, Settings, Login.

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
- **Gating modes:** `immediate`, `consent`, `delay`, `element`
- **SRI hash** computed server-side; snippet copy includes the correct
  `<script integrity=…>` tag
- **Rotation grace period:** previous loader keeps serving for 24h after
  regeneration; both `lk_…` IDs valid in parallel
- **Per-service rate limit:** 60 req/min per IP (Redis token bucket)

### Cookie Extension

Extend the lifetime of third-party cookies set by vendor tags.

- **Lifetime cap:** clamped to **395 days** (Chrome's max) at both DB
  (`CHECK` constraint) and service layer
- **Vendor compatibility matrix:** a JSON config of vendor URL → extension
  behavior
- **Logs:** IP-hashed (HMAC-SHA256), no raw IPs ever written
- **Purge job:** runs daily, removes `cookie_extension_logs` older than 90 days
- **Per-vendor rate limit:** 30 req/min per IP

See the full plan in [§15A & §15B of `HOSTAFFIN_SGTM_PLATFORM_PLAN.md`](./HOSTAFFIN_SGTM_PLATFORM_PLAN.md).

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
| POST   | `/api/v1/services/:id/loaders`      | admin  | create custom loader              |
| POST   | `/api/v1/services/:id/loaders/:lid/regenerate` | admin | rotate loader ID     |
| POST   | `/api/v1/services/:id/cookie-extensions`     | admin | add cookie extension    |
| POST   | `/api/v1/services/:id/cookie-extensions/:name/test` | admin | synthetic test     |
| GET    | `/loader.js?lid=…`                  | public | serve gated loader                |
| GET    | `/loader.js/run?lid=…`              | public | tracking pixel                    |
| GET    | `/cookie/extend/:name?v=…&t=…&rt=…` | public | set the extended cookie           |
| POST   | `/webhooks/whmcs`                   | HMAC   | WHMCS event receiver              |
| GET    | `/healthz`                          | —      | liveness                          |

---

## Operations

- **Add an edge node** → [`docs/runbooks/add-node.md`](./docs/runbooks/add-node.md)
- **Failover** → [`docs/runbooks/failover.md`](./docs/runbooks/failover.md)
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
| Provisioning       | Custom bash installer (Alma Linux 9) + Ansible roles  |
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
