# Build Summary — Hostaffin sGTM Hosting Platform

Generated on: 2026-06-23

This document summarizes what was scaffolded for the v1 platform based on
[`HOSTAFFIN_SGTM_PLATFORM_PLAN.md`](./HOSTAFFIN_SGTM_PLATFORM_PLAN.md).

## Repository layout

```
sGTM-Panel/
├── HOSTAFFIN_SGTM_PLATFORM_PLAN.md     # Full PRD + plan (~2200 lines)
├── BUILD_SUMMARY.md                    # this file
├── README.md                           # top-level quick start
├── Makefile                            # convenience targets
├── docker-compose.yml                  # local dev stack
├── .env.example                        # env template
│
├── control-plane/                      # Go + Fiber backend
│   ├── cmd/{api,worker,migrate,seed}/
│   ├── internal/
│   │   ├── auth/         # JWT + Argon2id
│   │   ├── config/
│   │   ├── db/           # pgx + sqlx
│   │   ├── domain/       # models
│   │   ├── handlers/     # Fiber routes
│   │   ├── observability/
│   │   ├── queue/        # Asynq
│   │   ├── redis/
│   │   ├── repos/        # 9 repos
│   │   └── services/     # 4 service packages
│   ├── migrations/       # 4 SQL migrations
│   ├── Dockerfile
│   └── README.md
│
├── node-agent/                         # Go binary
│   ├── cmd/agent/
│   ├── internal/{commands,config,heartbeat,metrics}/
│   ├── Dockerfile
│   └── README.md
│
├── admin-panel/                        # Next.js 14 + Shadcn
│   ├── app/(dashboard)/                 # dashboard, services, nodes, plans, etc.
│   ├── components/{ui,features,sidebar}/
│   ├── lib/{api,utils}.ts
│   ├── Dockerfile
│   └── README.md
│
├── whmcs-module/                        # PHP
│   └── modules/servers/hostaffin_sgtm/
│       ├── hostaffin_sgtm.php
│       ├── callback.php
│       ├── lib/{ApiClient,Hooks}.php
│       └── templates/clientarea.tpl
│
├── traefik/                            # Reverse proxy
│   ├── traefik.yml
│   ├── docker-compose.yml
│   └── sample-sgtm-stack.yml
│
├── infra/                              # Ops
│   ├── ansible/{playbook,roles}/
│   ├── systemd/
│   └── scripts/{bootstrap,rotate-jwt,backup}.sh
│
├── docs/                               # Reference docs
│   ├── api.md
│   ├── runbooks/{add-node,failover}.md
│   └── decisions/0001-swarm-over-k8s.md
│
└── .github/workflows/                  # CI
    ├── ci-control-plane.yml
    ├── ci-admin-panel.yml
    └── ci-whmcs-module.yml
```

## What was built

### 1. Control Plane (Go + Fiber)
- **HTTP API** with Fiber, JWT (RS256) auth, RBAC (super_admin / admin / support).
- **Repos**: users, plans, nodes, services, domains, loaders, cookie_extensions, audit_logs, usage.
- **Services** (business logic): provisioning, loaders, cookie_ext, auth.
- **Handlers**: auth, services, domains, loaders, cookie_ext, plans, nodes, users, audit.
- **Public endpoints**: `/loader.js`, `/loader.js/run`, `/cookie/extend/*` (rate-limited via Redis).
- **Worker**: asynq-based background job runner with registered task types.
- **Migrations**: 4 SQL files (users/plans/nodes/services/domains/usage/audit/loaders/cookie_extensions/ClickHouse DDL).
- **Seed**: creates 3 plans (Starter/Growth/Agency) + a super_admin.

### 2. Node Agent (Go)
- Talks to local Docker daemon (Swarm-aware).
- Heartbeat + metrics loops posting to the control plane.
- Command primitives for deploy / restart / delete (ready to be invoked by the worker over HTTPS).

### 3. Admin Panel (Next.js 14 + Shadcn UI)
- Sidebar with Dashboard, Services, Nodes, Plans, Users, Audit, Settings.
- Dashboard with KPI cards, plan distribution pie chart, node status list.
- Services table with status badges, click-through to detail page.
- Service detail page with **tabs**: Overview, **Loaders** (regenerate/copy snippet/SRI), **Cookie Extensions** (CRUD + test), Metrics.
- Add Cookie Extension dialog with vendor URL + lifetime (clamped to 395 days).
- Login page.
- Server-side fetchers via `/api/cp/*` rewrite to the control plane.

### 4. WHMCS Module (PHP)
- All required functions: `CreateAccount`, `SuspendAccount`, `UnsuspendAccount`, `TerminateAccount`, `ChangePackage`, `ClientAreaCustomButtonArray`, `ClientAreaOutput`, `AdminCustomButtonArray`.
- Custom fields auto-created for `service_id`, `edge_hostname`, `plan_slug`.
- HMAC-signed webhook callback for events from the control plane.
- Client-area panel template renders service status, usage, custom loader snippet, cookie extensions, domains.

### 5. Traefik
- Static config: HTTP→HTTPS redirect, ACME (Let's Encrypt), Docker Swarm provider.
- Reference compose stack.
- Sample service stack showing Traefik labels for: sGTM main, **Custom Loader** (`/loader.js`), **Cookie Extension** (`/cookie/`).

### 6. Infrastructure
- Ansible playbook + roles for `docker`, `traefik`, `node-agent`.
- systemd unit for the node-agent.
- Scripts: `bootstrap-node.sh`, `rotate-jwt.sh`, `backup.sh`.

### 7. CI / Docs
- GitHub Actions for control-plane (Go test+build), admin-panel (typecheck+lint+build), whmcs-module (PHP syntax).
- API reference (`docs/api.md`).
- Runbooks for adding a node and failover.
- ADR-0001 explaining why we chose Docker Swarm over Kubernetes.

## How to run locally

```bash
# 1. Boot the local dev stack
cp .env.example .env
docker compose up -d              # postgres + redis + clickhouse + traefik

# 2. Migrate + seed
cd control-plane
go run ./cmd/migrate up
go run ./cmd/seed                 # creates 3 plans + admin@hostaffin.local / ChangeMe!123

# 3. Run API + worker
go run ./cmd/api                  # :8080
go run ./cmd/worker

# 4. Run admin panel
cd ../admin-panel
npm install
cp .env.local.example .env.local
npm run dev                       # :3000
```

Default login: `admin@hostaffin.local` / `ChangeMe!123`.

## What's next

These items are **not yet implemented** (per the v1 scope in the plan):

- **Node agent ↔ control plane RPC** for actual container deploy/restart/delete. The control plane currently enqueues jobs and marks services active; the worker would call the node agent over HTTPS. The node agent already exposes the `commands` package.
- **ClickHouse ingestion** from `events_raw` → `events_5m`. The schema exists; the producer side is wired but the data pipeline should be enabled once metrics start flowing.
- **WHMCS webhook signing** in the control plane `MountWebhooks` is a stub — needs HMAC verification + event dispatch.
- **Admin Panel auth via cookie/JWT** — the login page stores the token in localStorage for now; production should use HttpOnly cookies via Next.js middleware.
- **Real node-agent / Docker integration** — the agent currently only posts heartbeats; once the deploy/restart/delete RPC contract is finalized it will call Docker.

The foundation is in place. Each of these is a focused iteration on top of the existing scaffolding.