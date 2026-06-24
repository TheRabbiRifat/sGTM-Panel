# Hostaffin sGTM Hosting Platform — Full Detailed Implementation Plan

> **Version:** 1.0 (Planning)
> **Audience:** Engineering Team, UI/UX Designers, AI Coding Agents
> **Status:** Draft for Review
> **Last Updated:** 2026-06-23

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Goals & Non-Goals](#2-goals--non-goals)
3. [System Architecture (Deep Dive)](#3-system-architecture-deep-dive)
4. [Repository & Project Structure](#4-repository--project-structure)
5. [Tech Stack Details](#5-tech-stack-details)
6. [Database Design (Full Schema)](#6-database-design-full-schema)
7. [WHMCS Module Design](#7-whmcs-module-design)
8. [Control Plane API (Backend)](#8-control-plane-api-backend)
9. [Node Agent Design](#9-node-agent-design)
10. [Docker Swarm & Container Management](#10-docker-swarm--container-management)
11. [Traefik + SSL Automation](#11-traefik--ssl-automation)
12. [Domain Management & Verification](#12-domain-management--verification)
13. [Usage Metering & ClickHouse Analytics](#13-usage-metering--clickhouse-analytics)
14. [Admin Panel (Next.js + Shadcn)](#14-admin-panel-nextjs--shadcn)
15. [WHMCS Client Area Integration](#15-whmcs-client-area-integration)
15A. [Custom Loader (Gated JS Snippet)](#15a-custom-loader-gated-js-snippet)
15B. [Cookie Extension Feature](#15b-cookie-extension-feature)
16. [Authentication, Authorization, RBAC](#16-authentication-authorization-rbac)
17. [Monitoring, Alerting, Observability](#17-monitoring-alerting-observability)
18. [Service Lifecycle State Machine](#18-service-lifecycle-state-machine)
19. [Quota & Overage Enforcement](#19-quota--overage-enforcement)
20. [Billing & Plan Management](#20-billing--plan-management)
21. [Background Workers & Queues](#21-background-workers--queues)
22. [Security Model](#22-security-model)
23. [CI/CD, Environments, Deployment Topology](#23-cicd-environments-deployment-topology)
24. [Development Milestones & Sprint Plan](#24-development-milestones--sprint-plan)
25. [Testing Strategy](#25-testing-strategy)
26. [Risks, Open Questions, Decisions Needed](#26-risks-open-questions-decisions-needed)
27. [Appendix: API Reference, Configs, Snippets](#27-appendix-api-reference-configs-snippets)

---

## 1. Executive Summary

**Hostaffin sGTM Hosting Platform** is a WHMCS-native, fully managed Server-side Google Tag Manager (sGTM) hosting product. Customers purchase and manage sGTM containers entirely from WHMCS as if they were shared hosting accounts. The platform automates provisioning, container lifecycle, domain/SSL, usage metering, and billing.

**Key idea:** WHMCS is the single customer-facing surface. Behind it, a Go-based Control Plane orchestrates a Docker Swarm cluster running sGTM containers, with Traefik for routing/SSL, PostgreSQL for state, Redis for queues/cache, and ClickHouse for analytics.

**Outcome:** A scalable, support-light, monthly-subscription sGTM hosting business with Starter / Growth / Agency plans.

---

## 2. Goals & Non-Goals

### 2.1 Goals (v1)

- One-click provisioning from WHMCS to a live sGTM endpoint in < 2 minutes.
- 100% automated SSL issuance and renewal via Traefik + Let's Encrypt.
- Per-container resource isolation (CPU/RAM) with hard Docker limits.
- Monthly request and bandwidth metering with dashboard visibility.
- Custom domain support with DNS verification flow.
- Admin panel for node, service, and plan management.
- GTM container editing endpoint like container config update.
- **Custom Loader (Gated JS Snippet) generation & rotation per service.**
- **Cookie Extension endpoint that rewrites first-party cookies via the sGTM container.**
- Near-zero touch support: restart/suspend/unsuspend is self-service or one-click.

### 2.2 Non-Goals (v1)

- No separate customer-facing sGTM panel.
- No Kubernetes (Docker Swarm only).
- No reseller hierarchy.
- No public-facing API.
- No multi-region / edge locations.
- No multi-user customer accounts.

---

## 3. System Architecture (Deep Dive)

### 3.1 High-Level Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                          CUSTOMER (Browser)                       │
│                              │                                   │
│                              ▼                                   │
│                  ┌──────────────────────┐                        │
│                  │       WHMCS          │  (Client Area)         │
│                  │  - Order Product     │                        │
│                  │  - View Service      │                        │
│                  │  - Add Domain        │                        │
│                  │  - Restart/Upgrade   │                        │
│                  └──────────┬───────────┘                        │
│                             │ WHMCS Module API                   │
│                             │ (CreateAccount, Suspend, etc.)     │
│                             ▼                                    │
│                  ┌──────────────────────┐                        │
│                  │  WHMCS Module PHP    │                        │
│                  │   (hooks + API)      │                        │
│                  └──────────┬───────────┘                        │
│                             │ HTTPS + JWT                        │
│                             ▼                                    │
│                  ┌──────────────────────┐                        │
│                  │   CONTROL PLANE API  │                        │
│                  │   (Go + Fiber)       │                        │
│                  │  ┌────────────────┐  │                        │
│                  │  │  Provisioner   │  │                        │
│                  │  │  Domain Mgr    │  │                        │
│                  │  │  Metering Agg. │  │                        │
│                  │  │  Quota Engine  │  │                        │
│                  │  │  Notifier      │  │                        │
│                  │  └────────────────┘  │                        │
│                  └──┬───────┬───────┬───┘                        │
│                     │       │       │                            │
│        ┌────────────┘       │       └────────────┐               │
│        ▼                    ▼                    ▼               │
│  ┌──────────┐        ┌──────────┐         ┌──────────────┐       │
│  │PostgreSQL│        │  Redis   │         │  ClickHouse  │       │
│  │ (state)  │        │ (queue,  │         │  (analytics) │       │
│  │          │        │  cache)  │         │              │       │
│  └──────────┘        └──────────┘         └──────────────┘       │
│                             │                                    │
│                  ┌──────────┴──────────┐                         │
│                  │   Admin Panel UI     │                        │
│                  │  (Next.js + Shadcn)  │                        │
│                  └──────────────────────┘                         │
│                             ▲                                    │
│                             │ HTTPS + JWT (admin)                │
│                             │                                    │
│   ┌─────────────────────────┴──────────────────────────┐         │
│   │              NODE AGENTS (per host)                 │         │
│   │  - Deploy/Delete/Restart container                  │         │
│   │  - Health metrics (cAdvisor/Prom)                   │         │
│   │  - gRPC/HTTPS reporting                            │         │
│   └──────────────┬──────────────────────────────────────┘         │
│                  │ Docker Swarm Manager                          │
│                  ▼                                                │
│   ┌──────────────────────────────────────────────┐                │
│   │   sGTM Containers (one per customer)         │                │
│   │   ┌────────┐  ┌────────┐  ┌────────┐         │                │
│   │   │ C-001  │  │ C-002  │  │ C-003  │  ...    │                │
│   │   └────────┘  └────────┘  └────────┘         │                │
│   └──────────────────────────────────────────────┘                │
│                  │                                                │
│                  ▼                                                │
│           ┌─────────────┐                                         │
│           │   Traefik   │ (ingress, routing, TLS)                 │
│           └──────┬──────┘                                         │
└──────────────────┼───────────────────────────────────────────────┘
                   ▼
              Public Internet
```

### 3.2 Component Responsibilities

| Component | Responsibility | Tech |
|---|---|---|
| WHMCS | Order, billing, customer surface | WHMCS PHP |
| WHMCS Module | Translate WHMCS events → Control Plane API | PHP |
| Control Plane API | Source of truth, orchestration | Go + Fiber |
| Admin Panel | Internal UI for staff/admins | Next.js + Shadcn |
| Node Agent | Local Docker ops, health reporting | Go binary |
| Docker Swarm | Container scheduling, replication | Docker Swarm |
| Traefik | Reverse proxy, TLS, routing | Traefik v3 |
| PostgreSQL | Service, user, plan, node, domain, audit | PostgreSQL 16 |
| Redis | Job queue, cache, rate-limit | Redis 7 |
| ClickHouse | Time-series usage/analytics | ClickHouse 24+ |
| sGTM Container | Actual Google Tag Manager server | `gcr.io/cloud-tagging-10302018/gtm-cloud-image:stable` |

### 3.3 Request Flow (Customer → sGTM)

1. End-user browser hits `https://track.client.com/...` also default one from us
2. DNS CNAMEs to a master node where Traefik is reachable.
3. Traefik matches host header → routes to specific sGTM container service in Swarm.
4. Traefik terminates TLS (Let's Encrypt cert).
5. Container handles GTM request.
6. Node agent / cAdvisor scrapes container metrics.
7. Metrics pushed to Control Plane → aggregated in ClickHouse.

---

## 4. Repository & Project Structure

### 4.1 Monorepo Layout

```
hostaffin-sgtm/
├── README.md
├── LICENSE
├── docker-compose.yml              # Local dev
├── docker-compose.prod.yml         # Reference prod
├── Makefile
├── .env.example
│
├── control-plane/                  # Go backend
│   ├── cmd/
│   │   ├── api/                    # Fiber HTTP server
│   │   ├── worker/                 # Background job runner
│   │   └── migrate/                # DB migration CLI
│   ├── internal/
│   │   ├── auth/                   # JWT, RBAC
│   │   ├── config/
│   │   ├── db/                     # SQLx/pgx repositories
│   │   ├── domain/                 # Domain models
│   │   ├── handlers/               # HTTP handlers
│   │   ├── services/               # Business logic
│   │   │   ├── provisioning/
│   │   │   ├── metering/
│   │   │   ├── domains/
│   │   │   ├── ssl/
│   │   │   ├── quota/
│   │   │   └── nodes/
│   │   ├── queue/                  # Asynq
│   │   ├── http/                   # Fiber app setup, middleware
│   │   ├── observability/          # Logger, metrics
│   │   └── clients/                # External clients (Traefik, etc.)
│   ├── migrations/                 # SQL migrations (golang-migrate)
│   ├── go.mod
│   └── go.sum
│
├── node-agent/                     # Go binary that runs on each node
│   ├── cmd/agent/
│   ├── internal/
│   │   ├── docker/                 # Docker SDK wrapper
│   │   ├── metrics/                # cAdvisor/scraper
│   │   ├── heartbeat/
│   │   └── commands/               # deploy, delete, restart
│   └── README.md
│
├── admin-panel/                    # Next.js + Shadcn
│   ├── app/
│   │   ├── (auth)/
│   │   ├── (dashboard)/
│   │   │   ├── services/
│   │   │   ├── nodes/
│   │   │   ├── plans/
│   │   │   ├── users/
│   │   │   └── settings/
│   │   ├── api/                    # BFF (optional)
│   │   └── layout.tsx
│   ├── components/
│   │   ├── ui/                     # Shadcn primitives
│   │   └── features/
│   ├── lib/
│   ├── public/
│   ├── package.json
│   ├── tailwind.config.ts
│   ├── next.config.mjs
│   └── tsconfig.json
│
├── whmcs-module/                   # PHP module
│   ├── modules/
│   │   └── servers/
│   │       └── hostaffin_sgtm/
│   │           ├── hostaffin_sgtm.php
│   │           ├── clientarea.tpl  (optional override)
│   │           └── lib/
│   │               ├── ApiClient.php
│   │               └── Hooks.php
│   └── README.md
│
├── traefik/                        # Configs
│   ├── traefik.yml
│   ├── dynamic/
│   │   └── routers.yml             # Generated from control plane
│   └── docker-compose.yml
│
├── infra/                          # IaC and scripts
│   ├── ansible/
│   │   ├── playbook-node.yml
│   │   └── roles/
│   │       ├── docker/
│   │       ├── traefik/
│   │       └── node-agent/
│   ├── scripts/
│   │   ├── bootstrap-node.sh
│   │   └── rotate-jwt.sh
│   └── systemd/
│       └── hostaffin-node-agent.service
│
├── docs/
│   ├── api.md
│   ├── architecture.md
│   ├── runbooks/
│   │   ├── add-node.md
│   │   ├── failover.md
│   │   └── rotate-certs.md
│   └── decisions/                  # ADRs
│
└── .github/
    └── workflows/
        ├── ci-control-plane.yml
        ├── ci-admin-panel.yml
        └── ci-whmcs-module.yml
```

### 4.2 Module Boundaries

- **Control Plane** is the only system allowed to mutate service/node state.
- **Node Agent** is the only system allowed to call Docker on its host.
- **Admin Panel** is read-mostly; all mutating actions go through Control Plane.
- **WHMCS Module** is the only entry point for customer-facing provisioning.

---

## 5. Tech Stack Details

| Layer | Choice | Rationale |
|---|---|---|
| Backend language | Go 1.22+ | Performance, static binaries, concurrency |
| HTTP framework | Fiber v2 | Fast, Express-like, low overhead |
| ORM/Query | sqlx + pgx | No magic, explicit SQL, fast |
| Migrations | golang-migrate | Standard, version-controlled SQL |
| Job queue | Asynq (Redis) | Reliable retries, scheduled jobs, UI-friendly |
| Cache | Redis 7 | Sessions, rate limit, fast reads |
| Analytics | ClickHouse 24+ | High cardinality time-series |
| Auth | JWT (RS256) + refresh tokens | Stateless, RBAC-friendly |
| Logging | zerolog + Loki | Structured JSON, fast |
| Tracing | OpenTelemetry | Optional but prepared |
| Container runtime | Docker Swarm | Simpler than K8s for v1 |
| Reverse proxy | Traefik v3 | Auto Let's Encrypt, Docker integration |
| Frontend | Next.js 14 App Router | Server components, RSC |
| UI Kit | Shadcn UI + Radix + Tailwind | Modern, accessible |
| Charts | Recharts or Tremor | Usage/analytics viz |
| Forms | React Hook Form + Zod | Type-safe validation |
| Data fetching | TanStack Query | Cache + revalidation |
| Tables | TanStack Table | Service/node tables |
| WHMCS Module | PHP 7.4+ | WHMCS requirement |
| Node agent | Go static binary | Single file deploy |
| CI | GitHub Actions | Standard, free tier |
| IaC | Ansible for nodes | Idempotent, well-known |

---

## 6. Database Design (Full Schema)

> **Engine:** PostgreSQL 16
> **Migrations:** `control-plane/migrations/*.up.sql`

### 6.1 `users`
```sql
CREATE TABLE users (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email        CITEXT UNIQUE NOT NULL,
  password     TEXT NOT NULL,             -- argon2 hash
  role         TEXT NOT NULL CHECK (role IN ('super_admin','admin','support')),
  whmcs_client_id INT UNIQUE,             -- link to WHMCS user
  is_active    BOOLEAN NOT NULL DEFAULT TRUE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_users_role ON users(role);
```

### 6.2 `plans`
```sql
CREATE TABLE plans (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  whmcs_product_id INT UNIQUE NOT NULL,    -- WHMCS product link
  name            TEXT NOT NULL,
  slug            TEXT UNIQUE NOT NULL,
  cpu_limit       NUMERIC(4,2) NOT NULL,   -- vCPU
  ram_limit_mb    INT NOT NULL,
  request_limit   BIGINT NOT NULL,         -- monthly
  bandwidth_limit_gb INT NOT NULL,
  container_replicas INT NOT NULL DEFAULT 1,
  price_cents     INT NOT NULL,
  currency        CHAR(3) NOT NULL DEFAULT 'USD',
  is_active       BOOLEAN NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

### 6.3 `nodes`
```sql
CREATE TABLE nodes (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  hostname        TEXT UNIQUE NOT NULL,
  region          TEXT,
  status          TEXT NOT NULL CHECK (status IN ('online','offline','draining','maintenance','disabled')),
  total_cpu       NUMERIC(4,2),
  total_ram_mb    INT,
  used_cpu        NUMERIC(4,2) DEFAULT 0,
  used_ram_mb     INT DEFAULT 0,
  container_count INT DEFAULT 0,
  last_heartbeat  TIMESTAMPTZ,
  agent_version   TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_nodes_status ON nodes(status);
```

### 6.4 `services`
```sql
CREATE TABLE services (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  whmcs_service_id    INT UNIQUE NOT NULL,
  whmcs_client_id     INT NOT NULL,
  plan_id             UUID NOT NULL REFERENCES plans(id),
  node_id             UUID REFERENCES nodes(id),
  container_id        TEXT,                 -- Docker container ID
  container_name      TEXT UNIQUE,
  status              TEXT NOT NULL CHECK (status IN
                      ('pending','provisioning','active','suspended',
                       'terminated','failed')),
  edge_hostname       TEXT UNIQUE NOT NULL, -- abc123.edge.hostaffin.com
  failure_reason      TEXT,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  activated_at        TIMESTAMPTZ,
  terminated_at       TIMESTAMPTZ
);
CREATE INDEX idx_services_status ON services(status);
CREATE INDEX idx_services_node ON services(node_id);
CREATE INDEX idx_services_whmcs_client ON services(whmcs_client_id);
```

### 6.5 `domains`
```sql
CREATE TABLE domains (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_id      UUID NOT NULL REFERENCES services(id) ON DELETE CASCADE,
  domain          TEXT UNIQUE NOT NULL,
  is_primary      BOOLEAN NOT NULL DEFAULT FALSE,
  ssl_status      TEXT NOT NULL DEFAULT 'pending'
                  CHECK (ssl_status IN ('pending','issued','renewing','failed')),
  verified        BOOLEAN NOT NULL DEFAULT FALSE,
  verification_token TEXT,
  last_checked_at TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_domains_service ON domains(service_id);
```

### 6.6 `usage_daily` (Postgres rollup)
```sql
CREATE TABLE usage_daily (
  service_id    UUID NOT NULL REFERENCES services(id) ON DELETE CASCADE,
  date          DATE NOT NULL,
  requests      BIGINT NOT NULL DEFAULT 0,
  bandwidth_b   BIGINT NOT NULL DEFAULT 0,
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (service_id, date)
);
```

### 6.7 `audit_logs`
```sql
CREATE TABLE audit_logs (
  id          BIGSERIAL PRIMARY KEY,
  user_id     UUID REFERENCES users(id),
  actor_type  TEXT NOT NULL,           -- 'admin','system','whmcs'
  action      TEXT NOT NULL,           -- e.g. 'service.restart'
  resource    TEXT,                    -- e.g. 'service:uuid'
  metadata    JSONB,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_audit_action ON audit_logs(action);
CREATE INDEX idx_audit_created ON audit_logs(created_at DESC);
```

### 6.8 `webhooks_outbox`
```sql
CREATE TABLE webhooks_outbox (
  id          BIGSERIAL PRIMARY KEY,
  event       TEXT NOT NULL,
  payload     JSONB NOT NULL,
  delivered   BOOLEAN NOT NULL DEFAULT FALSE,
  attempts    INT NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

### 6.9 ClickHouse Tables

```sql
-- Raw events from node agents
CREATE TABLE events_raw (
  ts          DateTime64(3),
  service_id  UUID,
  node_id     UUID,
  requests    UInt64,
  bytes_in    UInt64,
  bytes_out   UInt64,
  cpu_pct     Float32,
  ram_mb      UInt32,
  status_code UInt16
) ENGINE = MergeTree
PARTITION BY toYYYYMM(ts)
ORDER BY (service_id, ts);

-- Aggregated 5-minute rollup
CREATE TABLE events_5m (
  ts          DateTime,
  service_id  UUID,
  requests    UInt64,
  bytes_in    UInt64,
  bytes_out   UInt64,
  cpu_avg     Float32,
  ram_avg     Float32
) ENGINE = SummingMergeTree
PARTITION BY toYYYYMM(ts)
ORDER BY (service_id, ts);
```

---

## 7. WHMCS Module Design

### 7.1 File: `hostaffin_sgtm.php`

Required WHMCS module functions:

- `hostaffin_sgtm_MetaData()`
- `hostaffin_sgtm_ConfigOptions()`
- `hostaffin_sgtm_CreateAccount($params)`
- `hostaffin_sgtm_SuspendAccount($params)`
- `hostaffin_sgtm_UnsuspendAccount($params)`
- `hostaffin_sgtm_TerminateAccount($params)`
- `hostaffin_sgtm_ChangePackage($params)` — for upgrades
- `hostaffin_sgtm_ClientAreaCustomButtonArray()` — buttons in client area
- `hostaffin_sgtm_ClientAreaOutput($params)` — inject custom panel HTML

### 7.2 Configurable Options (Module Settings)

```
API Base URL: https://control-plane.hostaffin.com
API Key: ********
Webhook Secret: ********
Default Plan Mapping: JSON {whmcs_pid: plan_slug}
```

### 7.3 CreateAccount Flow

```php
$resp = $api->post('/api/services', [
  'whmcs_service_id' => $params['serviceid'],
  'whmcs_client_id'  => $params['userid'],
  'plan_slug'        => $params['configoption1'],
  'domain'           => $params['domain'],
]);
if ($resp->status === 'pending' || $resp->status === 'active') {
  return 'success';
}
return $resp->error;
```

### 7.4 ClientArea Buttons

The module returns custom buttons (Restart, Add Domain, Verify DNS) which WHMCS displays inside the service page. They are GET/POST links that hit a small PHP handler which then proxies to the Control Plane API.

### 7.5 Webhook Receiver

`/modules/servers/hostaffin_sgtm/callback.php` receives:
- `service.provisioned`
- `service.failed`
- `service.suspended`
- `domain.verified`
- `ssl.issued`
- `ssl.failed`
- `quota.exceeded`

Used to update WHMCS service status & email customer.

### 7.6 Upgrade Flow (ChangePackage)

```php
$api->post("/api/services/{$service_id}/upgrade", [
  'plan_slug' => $params['configoption1'],
]);
```

WHMCS performs proration automatically. Control Plane resizes container (CPU/RAM) on next deploy or via in-place Docker update.

---

## 8. Control Plane API (Backend)

### 8.1 Framework Setup (Fiber)

```go
app := fiber.New(fiber.Config{
  DisableStartupMessage: true,
  ErrorHandler:          customErrorHandler,
  BodyLimit:             1 * 1024 * 1024,
})

app.Use(recover.New())
app.Use(requestid.New())
app.Use(zerologMiddleware)
app.Use(cors.New(cors.Config{ AllowOrigins: allowedOrigins }))

// health
app.Get("/healthz", ...)

// public webhook
app.Post("/webhooks/whmcs", whmcsWebhook)

// v1
v1 := app.Group("/api", authMiddleware, rbacMiddleware)
```

### 8.2 Auth Middleware

- Expects `Authorization: Bearer <jwt>`.
- JWT signed with RS256 (rotate via `kid`).
- RBAC decorator: `rbac.Require("admin","super_admin")`.
- Service-to-service (Node Agent, WHMCS module) uses scoped API keys + mTLS optional.

### 8.3 Services Endpoints

```
POST   /api/services
GET    /api/services
GET    /api/services/:id
GET    /api/services/:id/usage
GET    /api/services/:id/metrics
POST   /api/services/:id/restart
POST   /api/services/:id/suspend
POST   /api/services/:id/unsuspend
POST   /api/services/:id/upgrade
DELETE /api/services/:id
POST   /api/services/:id/move
```

### 8.3.1 Loader Endpoints

```
GET    /api/services/:id/loaders
POST   /api/services/:id/loaders
GET    /api/loaders/:loader_id
PUT    /api/loaders/:loader_id/config
POST   /api/loaders/:loader_id/regenerate
POST   /api/loaders/:loader_id/disable
GET    /api/loaders/:loader_id/analytics
```

### 8.3.2 Cookie Extension Endpoints

```
GET    /api/services/:id/cookie-extensions
POST   /api/services/:id/cookie-extensions
PUT    /api/cookie-extensions/:id
DELETE /api/cookie-extensions/:id
POST   /api/cookie-extensions/:id/test
GET    /api/cookie-extensions/:id/analytics
GET    /api/services/:id/cookie-extension-logs
```

### 8.4 Provisioning Service (Go, pseudo-code)

```go
func (s *ProvisioningService) Create(ctx, cmd CreateServiceCmd) (*Service, error) {
  // 1. Persist service row status=pending
  svc, err := s.repo.CreateService(ctx, ...)
  if err != nil { return nil, err }

  // 2. Enqueue async job
  err = s.queue.Enqueue(ctx, "provision", ProvisionJob{ServiceID: svc.ID})
  if err != nil { return svc, nil }  // row will be picked by worker

  return svc, nil
}

func (w *Worker) HandleProvision(ctx, j ProvisionJob) error {
  svc, _ := w.repo.GetService(ctx, j.ServiceID)
  svc.SetStatus("provisioning")
  node, _ := w.scheduler.PickNode(ctx, svc.Plan)
  err := w.nodeClient.Deploy(ctx, node, DeploymentSpec{
    ContainerName: svc.ContainerName,
    Image:         "ghcr.io/googleanalytics/gtm-server-side:latest",
    Env: map[string]string{
      "CONTAINER_CONFIG":   svc.ContainerConfigURL,
      "PREVIEW_SERVER_URL": svc.PreviewURL,
    },
    CPULimit:  svc.Plan.CPULimit,
    RAMLimit:  svc.Plan.RAMLimitMB,
    Labels:    map[string]string{"hostaffin.service_id": svc.ID.String()},
    Networks:  []string{"hostaffin_edge"},
  })
  if err != nil {
    svc.SetStatus("failed"); svc.FailureReason = err.Error()
    return err
  }
  // 3. Register Traefik router (via Docker labels)
  // 4. Update service status=active
  svc.SetStatus("active")
  svc.ActivatedAt = time.Now()
  return nil
}
```

### 8.5 Service & Handler Skeleton

```go
// internal/handlers/services.go
func (h *Handler) Create(c *fiber.Ctx) error {
  var req dto.CreateServiceRequest
  if err := c.BodyParser(&req); err != nil {
    return fiber.NewError(fiber.StatusBadRequest, "invalid body")
  }
  svc, err := h.svc.Create(c.Context(), req)
  if err != nil { return err }
  return c.Status(201).JSON(svc)
}
```

### 8.6 Domain Endpoints

```
POST   /api/services/:id/domains
GET    /api/services/:id/domains
POST   /api/domains/:id/verify
DELETE /api/domains/:id
```

### 8.7 Plans / Nodes / Users (Admin)

```
GET    /api/plans
POST   /api/plans
PUT    /api/plans/:id
GET    /api/nodes
POST   /api/nodes
POST   /api/nodes/:id/drain
POST   /api/nodes/:id/maintenance
GET    /api/users
POST   /api/users
PUT    /api/users/:id
```

### 8.8 Webhooks (incoming from WHMCS, Node Agents)

```
POST /webhooks/whmcs
POST /webhooks/nodes/:node_id
```

Each request is HMAC-signed; signature header `X-Hostaffin-Signature`.

### 8.9 Error Model

```json
{
  "error": {
    "code": "service.provision_failed",
    "message": "Human readable",
    "request_id": "..."
  }
}
```

---

## 9. Node Agent Design

### 9.1 Responsibilities

- Run as systemd service `hostaffin-node-agent` on each Swarm worker/manager.
- Authenticate to control plane via JWT (short-lived, rotated).
- Receive commands: `deploy`, `delete`, `restart`, `redeploy`.
- Stream container metrics every 10s to control plane.
- Run lightweight HTTP server on `127.0.0.1:9100` (Prometheus-friendly).

### 9.2 Command Protocol

Control Plane → Agent over HTTPS:

```json
{
  "cmd": "deploy",
  "request_id": "...",
  "payload": {
    "container_name": "sgtm_abc123",
    "image": "gcr.io/cloud-tagging-10302018/gtm-cloud-image:stable",
    "env": {...},
    "cpu_limit": 0.5,
    "ram_limit_mb": 512,
    "labels": {
      "traefik.enable": "true",
      "traefik.http.routers.abc123.rule": "Host(`abc123.edge.hostaffin.com`)",
      "traefik.http.routers.abc123.tls.certresolver": "letsencrypt"
    }
  }
}
```

### 9.3 Metrics Stream

Agent → Control Plane (POST `/webhooks/nodes/{id}/metrics`):

```json
{
  "ts": "2026-06-23T10:00:00Z",
  "containers": [
    {
      "container_id": "...",
      "service_id": "...",
      "cpu_pct": 12.4,
      "ram_mb": 230,
      "net_in_b": 1234,
      "net_out_b": 5678,
      "restart_count": 0
    }
  ],
  "node": {
    "cpu_pct": 38.2,
    "ram_used_mb": 12000,
    "ram_total_mb": 32000,
    "disk_used_pct": 41
  }
}
```

Agent then writes to ClickHouse via Control Plane's ingestion API.

### 9.4 Deployment Topology

- **Manager node(s):** run Traefik + Control Plane worker can also be here.
- **Worker nodes:** host sGTM containers + node-agent.
- **Master label:** `hostaffin_role=master` — every node is a master node;
  there is no separate "edge" or "slave" role. All nodes can run Traefik.

---

## 10. Docker Swarm & Container Management

### 10.1 Init

```bash
docker swarm init --advertise-addr <MANAGER_IP>
docker swarm join --token <TOKEN> <MANAGER_IP>:2377
```

### 10.2 Networks

- `hostaffin_edge` — overlay network used by Traefik and sGTM containers.
- `hostaffin_internal` — overlay for control plane ↔ agent (not exposed publicly).

### 10.3 Container Spec (sGTM)

```yaml
# Generated dynamically per service
services:
  sgtm_abc123:
    image: gcr.io/cloud-tagging-10302018/gtm-cloud-image:stable
    environment:
      CONTAINER_CONFIG: 
    networks:
      - hostaffin_edge
    deploy:
      resources:
        limits:
          cpus: '0.50'
          memory: 512M
        reservations:
          cpus: '0.10'
          memory: 128M
      restart_policy:
        condition: on-failure
        max_attempts: 5
    labels:
      traefik.enable: "true"
      traefik.http.routers.sgtm_abc123.rule: "Host(`abc123.edge.hostaffin.com`)"
      traefik.http.routers.sgtm_abc123.tls: "true"
      traefik.http.routers.sgtm_abc123.tls.certresolver: letsencrypt
      traefik.http.services.sgtm_abc123.loadbalancer.server.port: "8080"
      hostaffin.service_id: "<UUID>"
      hostaffin.plan_slug: "starter"
```

### 10.4 Node Selection Algorithm

```go
func PickNode(nodes []Node, plan Plan) (Node, error) {
  candidates := []Node{}
  for _, n := range nodes {
    if n.Status != "online" { continue }
    if n.Maintenance { continue }
    if n.UsedCPU + plan.CPULimit > n.TotalCPU { continue }
    if n.UsedRAM + plan.RAMLimitMB > n.TotalRAM { continue }
    candidates = append(candidates, n)
  }
  if len(candidates) == 0 { return Node{}, ErrNoCapacity }
  // least-loaded first
  sort.Slice(candidates, func(i, j int) bool {
    return score(candidates[i]) < score(candidates[j])
  })
  return candidates[0], nil
}
```

Score = `(used_cpu/total_cpu + used_ram/total_ram) / 2`.

### 10.5 Container Limits

- `cpus: '0.50'`, `memory: 512M` hard limits.
- `pids_limit: 256` (prevents fork bombs).
- `read_only: true` root FS where possible.
- `cap_drop: [ALL]` + minimal capabilities.

---

## 11. Traefik + SSL Automation

### 11.1 Static Config (`traefik.yml`)

```yaml
entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"

providers:
  docker:
    swarmMode: true
    exposedByDefault: false
    network: hostaffin_edge

certificatesResolvers:
  letsencrypt:
    acme:
      email: ops@hostaffin.com
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web

api:
  dashboard: true
  insecure: false

log:
  level: INFO
  format: json
```

### 11.2 Dynamic Routing

Traefik auto-discovers services from Docker labels — no manual router config needed. Control Plane writes labels when deploying.

### 11.3 SSL States

- `pending`: container just deployed, Traefik issuing cert.
- `issued`: cert present in acme.json + matching hostname.
- `renewing`: < 30 days to expiry.
- `failed`: ACME error, alert.

Sync: a periodic job in control plane queries Traefik API or checks acme.json to update `domains.ssl_status`.

### 11.4 Wildcard Option (v2)

For agencies, v2 may add wildcard certs via DNS-01 (Cloudflare plugin). v1 is per-hostname only.

---

## 12. Domain Management & Verification

### 12.1 Add Custom Domain Flow

1. Customer submits `track.client.com` in WHMCS.
2. WHMCS module → Control Plane `POST /api/services/{id}/domains`.
3. Control Plane:
   - Generates `verification_token` (random 32 chars).
   - Stores `domain` row with `verified=false`.
   - Returns DNS instructions:
     ```
     CNAME  track.client.com  → abc123.edge.hostaffin.com
     TXT    _hostaffin-verify.track.client.com  → "hostaffin-verify=<token>"
     ```
4. Customer adds records.
5. Customer clicks "Verify DNS" → WHMCS → Control Plane `POST /api/domains/{id}/verify`.
6. Control Plane runs DNS checks (Go `github.com/miekg/dns`):
   - Resolve `track.client.com` CNAME → must equal `abc123.edge.hostaffin.com`.
   - Resolve TXT and confirm token.
7. If valid → `verified=true`; Traefik issues cert; `ssl_status` updates to `issued`.

### 12.2 DNS Checker

```go
func VerifyCNAME(host, expected string) (bool, error) {
  c := dns.Client{}
  m := dns.Msg{}
  m.SetQuestion(dns.Fqdn(host), dns.TypeCNAME)
  in, _, err := c.Exchange(&m, "1.1.1.1:53")
  if err != nil { return false, err }
  for _, a := range in.Answer {
    if cn, ok := a.(*dns.CNAME); ok {
      if strings.EqualFold(cn.Target, expected) { return true, nil }
    }
  }
  return false, nil
}
```

### 12.3 Background Retry

A scheduled job retries unverified domains every 5 minutes for up to 7 days. Sends reminder emails via WHMCS email template at 1h, 24h, 72h.

---

## 13. Usage Metering & ClickHouse Analytics

### 13.1 Collection Points

- **Traefik access logs** → shipped via Promtail/Loki OR parsed by node-agent and posted to control plane.
- **cAdvisor** metrics on each host → CPU, RAM per container.
- **Request counter**: a small Go sidecar or in-container exporter increments a counter per request. Recommended: use Traefik access log + ClickHouse ingestion.

### 13.2 Pipeline

```
Traefik access log (JSON)
   ↓ Promtail / Filebeat
Loki (optional for v1; ClickHouse-direct preferred)

or

Node Agent scrapes Traefik metrics
   ↓
Control Plane ingestion API
   ↓
ClickHouse events_raw
   ↓ (Materialized View every 5 min)
events_5m
   ↓
PostgreSQL usage_daily (nightly rollup)
```

### 13.3 Control Plane Ingestion API

```
POST /internal/ingest/metrics
{
  "ts": "...",
  "events": [
    {
      "service_id": "...",
      "requests_delta": 12,
      "bytes_in_delta": 2345,
      "bytes_out_delta": 3456,
      "cpu_pct": 10.2,
      "ram_mb": 200
    }
  ]
}
```

Writes:
1. Bulk insert into `events_raw` (ClickHouse).
2. Update Redis counters for the current billing cycle.
3. Periodic job writes to `usage_daily`.

### 13.4 Quota Check

Before accepting any new request count, control plane checks:

```go
if usageThisMonth+newRequests > plan.RequestLimit {
  if globalPolicy == "suspend" { svc.Suspend() }
  if globalPolicy == "overage" { svc.FlagOverage(); notify() }
}
```

---

## 14. Admin Panel (Next.js + Shadcn)

### 14.1 Routes

```
/login
/dashboard
/services
  /[id]
  /[id]/loaders
  /[id]/cookie-extensions
/nodes
  /[id]
/plans
/users
/settings
  /general
  /alerts
  /billing-policies
/audit-logs
/login-activities
```

### 14.2 Tech Setup

- `app/` directory with server components.
- `lib/api.ts` — typed fetch wrappers to control plane (server-side uses API key from env).
- `middleware.ts` — checks JWT cookie, redirects to `/login`.
- Reusable components in `components/ui` (Shadcn).
- Feature components: `ServiceTable`, `NodeCard`, `PlanForm`, `MetricsChart`.

### 14.3 Key Pages

#### `/dashboard`

Cards:
- Active / Suspended / Failed counts
- Requests today / this month
- Bandwidth today / this month
- MRR (sum of active plans price)
- Node utilization table

Charts (Recharts):
- Requests/min line chart (last 24h)
- Per-plan distribution pie
- Top 10 services by traffic

#### `/services`

Searchable, filterable table:
- Columns: Service ID, Customer, Plan, Status, Node, CPU, RAM, Requests, Bandwidth, Created
- Row click → `/services/[id]`

#### `/services/[id]`

Tabs:
- Overview
- Domains
- **Loaders** (list loaders, regenerate, copy snippet, view analytics)
- **Cookie Extensions** (list, add, edit, test, view logs)
- Metrics (time-series charts)
- Logs (audit)
- Actions (Restart, Suspend, Unsuspend, Terminate, Move Node, Upgrade)

#### `/nodes`

- Grid view of nodes with health card.
- Per-node: container list, CPU/RAM, restart counts.
- Buttons: Maintenance, Drain, Disable.

#### `/plans`

- Plan CRUD.
- Edit price, request limit, CPU/RAM.

#### `/settings/alerts`

- Channels: email, Telegram, Discord.
- Triggers and thresholds.

### 14.4 Auth

- Admin Panel uses its own login (email/password) hitting Control Plane `/api/auth/login`.
- Token stored as HttpOnly cookie; refresh token rotated.

### 14.5 Theming

- Shadcn default with light/dark mode (next-themes).
- Brand color: Hostaffin primary.

---

## 15. WHMCS Client Area Integration

### 15.1 What Customer Sees

When opening a Hostaffin sGTM service in WHMCS client area, the module renders:

```
┌────────────────────────────────────────────────────────┐
│  sGTM Starter                                          │
│  Status: ● Active                                      │
│                                                        │
│  Container URL                                         │
│  https://abc123.edge.hostaffin.com                     │
│                                                        │
│  Plan: Starter (0.5 vCPU · 512 MB · 500k req/mo)       │
│                                                        │
│  Usage this month: 124,531 / 500,000 requests          │
│  Bandwidth this month: 2.1 GB                          │
│                                                        │
│  Custom Domains                                        │
│  ┌──────────────────────────────┬────────┬───────────┐ │
│  │ Domain                       │ SSL    │ Verified  │ │
│  ├──────────────────────────────┼────────┼───────────┤ │
│  │ track.client.com             │ Issued │ Yes       │ │
│  └──────────────────────────────┴────────┴───────────┘ │
│                                                        │
│  [ Add Domain ]  [ Verify DNS ]  [ Restart ]           │
│  [ Upgrade Plan ]                                      │
└────────────────────────────────────────────────────────┘
```

### 15.2 Implementation

- WHMCS module's `ClientAreaOutput` returns HTML rendered server-side with values from `/api/services/{id}`.
- Buttons post to module's PHP handler → proxied to control plane → page re-renders.
- For real-time data, embedded iframe to Admin Panel scoped view is **not** used in v1; everything is server-rendered.

### 15.3 Client Area Templates (optional override)

Override `clientarea.tpl` in module to fully customize the panel. For v1, the default WHMCS styling is fine.

### 15.4 Loader & Cookie Section (UI)

In the WHMCS client area, below the existing "Custom Domains" panel, render two extra cards:

```
┌────────────────────────────────────────────────────────┐
│  Custom Loader                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │ <script async src="https://abc123.edge.hostaffin  │ │
│  │ .com/loader.js?id=lk_8f3a2c1b"></script>          │ │
│  └────────────────────────────────────────────────────┘ │
│  [ Copy Snippet ]   [ Regenerate Loader ID ]            │
│  Status: Active   Created: 2026-06-23                   │
└────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────┐
│  Cookie Extension                                       │
│  Endpoint:                                              │
│  https://abc123.edge.hostaffin.com/cookie/extend        │
│                                                        │
│  Configured cookies:                                    │
│  ┌────────────┬────────────┬────────────┬────────────┐  │
│  │ Cookie     │ Original   │ Lifetime   │ Status     │  │
│  ├────────────┼────────────┼────────────┼────────────┤  │
│  │ _ga        │ 2 years    │ 13 months  │ Active     │  │
│  │ _fbp       │ 90 days    │ 13 months  │ Active     │  │
│  └────────────┴────────────┴────────────┴────────────┘  │
│  [ Add Cookie ]  [ Test Extension ]                     │
└────────────────────────────────────────────────────────┘
```

---

## 15A. Custom Loader (Gated JS Snippet)

### 15A.1 What it is

A small, **first-party** JavaScript snippet served from the customer's own sGTM container. The loader is **gated** — it only fires after a configurable trigger (e.g. cookie consent, specific event, or page delay) and dispatches a payload into sGTM where the customer can run server-side tags.

This is the modern equivalent of `gtm.js` but **fully owned** by the customer and served from their own domain (avoiding ad-blocker stripping and ITP limitations).

### 15A.2 Goals

- Generate a unique `loader_id` per service at provisioning time.
- Serve a static, cacheable, minified `loader.js` from Traefik → sGTM container.
- Allow regeneration (rotation) of the `loader_id` if leaked.
- Provide a "Preview Loader" mode that points to the sGTM preview server.
- Track loader hit counts (per `loader_id`) for usage analytics.

### 15A.3 Data Model (new tables)

```sql
CREATE TABLE loaders (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_id    UUID NOT NULL REFERENCES services(id) ON DELETE CASCADE,
  loader_id     TEXT UNIQUE NOT NULL,       -- e.g. "lk_8f3a2c1b"
  version       INT NOT NULL DEFAULT 1,     -- bumped on regeneration
  mode          TEXT NOT NULL DEFAULT 'live'  -- 'live' | 'preview'
                CHECK (mode IN ('live','preview')),
  is_active     BOOLEAN NOT NULL DEFAULT TRUE,
  hit_count     BIGINT NOT NULL DEFAULT 0,
  last_hit_at   TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  rotated_at    TIMESTAMPTZ
);
CREATE INDEX idx_loaders_service ON loaders(service_id);

CREATE TABLE loader_configs (
  loader_id     TEXT PRIMARY KEY REFERENCES loaders(loader_id) ON DELETE CASCADE,
  trigger_type  TEXT NOT NULL DEFAULT 'immediate'
                CHECK (trigger_type IN ('immediate','consent','delay','element')),
  trigger_value TEXT,                        -- e.g. "2000" (ms) or CSS selector
  cookie_name   TEXT,                        -- consent cookie name
  respect_dnt   BOOLEAN NOT NULL DEFAULT TRUE,
  allow_bots    BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

### 15A.4 Provisioning Hook

When a service transitions to `active`, control plane:

1. Generates `loader_id = "lk_" + 8 random hex chars` (collision-checked).
2. Inserts `loaders` row + default `loader_configs` row.
3. Adds Traefik route:
   ```
   Host(`abc123.edge.hostaffin.com`) && Path(`/loader.js`)
     → service sgtm_abc123 (port 8080)
     AddHeader: Cache-Control: public, max-age=300
   ```
4. Injects env into the sGTM container:
   ```
   LOADER_ID=lk_8f3a2c1b
   LOADER_TRIGGER=immediate
   LOADER_RESPECT_DNT=true
   ```

### 15A.5 Loader File Layout (inside sGTM container)

A pre-bundled static asset is mounted into the container at build time:

```
container/
  /opt/gtm-server/loader/
    loader.js          # default scaffold
    loader.min.js      # minified version
    loader.template.js # template the container renders dynamically
```

The container's HTTP server exposes:
- `GET /loader.js?id={loader_id}` — returns the customer-configured loader, with the `loader_id` interpolated, plus the `data-loader-id` attribute.
- The response is served with `Content-Type: application/javascript` and a short cache TTL.

### 15A.6 Default Loader Template

```js
// Returned by GET /loader.js?id={loader_id}
(function (w, d, s, id) {
  if (w.__hostaffinLoaderLoaded) return;
  w.__hostaffinLoaderLoaded = true;
  if (navigator.doNotTrack === '1' && RESPECT_DNT) return;
  if (/bot|crawl|spider/i.test(navigator.userAgent) && !ALLOW_BOTS) return;

  var gj = d.createElement(s);
  var r  = d.getElementsByTagName(s)[0];
  gj.async = true;
  gj.src   = 'https://EDGE_HOST/loader.js?run=1&id=' + encodeURIComponent(id);
  gj.setAttribute('data-loader-id', id);
  r.parentNode.insertBefore(gj, r);
})(window, document, 'script', 'lk_8f3a2c1b');
```

When `?run=1` is set, the container returns a tiny **runtime** payload that pushes a `loader_hit` event into the sGTM `dataLayer`-equivalent endpoint and dispatches the configured consent/event into the GTM container.

### 15A.7 Control Plane Endpoints

```
GET    /api/services/:id/loaders
POST   /api/services/:id/loaders             # add additional loader (e.g. preview)
GET    /api/loaders/:loader_id
PUT    /api/loaders/:loader_id/config        # update trigger/respect_dnt/etc
POST   /api/loaders/:loader_id/regenerate    # rotate id; old becomes inactive
POST   /api/loaders/:loader_id/disable
GET    /api/loaders/:loader_id/analytics     # hit counts over time
```

### 15A.8 WHMCS Module Actions

`ClientAreaCustomButtonArray()` adds:
- `Copy Loader Snippet` (client-side JS copies to clipboard).
- `Regenerate Loader ID` (POST to module → `/api/loaders/:id/regenerate`).

### 15A.9 Loader Hit Metering

- `loader.js?run=1` endpoint increments Redis counter `loader:{loader_id}:hits:{YYYY-MM-DD}`.
- Nightly job rolls up to `usage_daily` and to ClickHouse.
- Counts toward plan request quota (each `?run=1` hit = 1 request unit).
- Visible in WHMCS usage card as "Loader Hits".

### 15A.10 Security

- `loader_id` is unguessable (8 bytes = 64-bit entropy).
- Rotation invalidates the old id within 60 seconds (Traefik router update + container env refresh).
- `data-loader-id` attribute lets the customer detect unauthorized usage in their analytics.
- Rate limit: 60 req/min/IP on `/loader.js`.
- SRI (Subresource Integrity) hash is computed and shown next to the snippet so customers can pin it.

### 15A.11 Preview Mode

- Generates a second `loader_id` with `mode='preview'`.
- Points to the sGTM preview server URL (`https://preview.edge.hostaffin.com/...`).
- Used by customers testing changes in GTM's preview mode.
- Disabled by default; admin can enable per service.

---

## 15B. Cookie Extension Feature

### 15B.1 What it is

The Cookie Extension rewrites third-party tracking cookies (`_ga`, `_fbp`, `_tt`, etc.) so they appear to be **first-party** cookies on the customer's site — set by their own domain, not by the vendor. This is done by routing the cookie set/get through the customer's sGTM container, which proxies to the vendor while issuing a same-site cookie.

This is critical for:
- Surviving Safari ITP and Firefox ETP.
- Bypassing ad-blockers that strip known third-party cookies.
- Bypassing CNAME-cloaking detection (we are not cloaking — we expose the endpoint as the customer's own subdomain).

### 15B.2 Goals

- Expose a **stable HTTP endpoint** on the customer's domain: `https://<custom_domain>/cookie/extend` (or the default edge hostname).
- Allow customer to register cookies with: original name, target vendor URL, new lifetime.
- Set extended-lifetime cookies on the customer's domain.
- Proxy pixel/fingerprint requests to the original vendor through sGTM (so vendor sees a server-side call but customer owns the cookie).
- Provide a "Test Extension" tool that simulates a request and shows the resulting `Set-Cookie` header.

### 15B.3 Data Model

```sql
CREATE TABLE cookie_extensions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_id      UUID NOT NULL REFERENCES services(id) ON DELETE CASCADE,
  cookie_name     TEXT NOT NULL,                 -- e.g. "_ga"
  vendor_url      TEXT NOT NULL,                 -- e.g. "https://www.google-analytics.com/..."
  new_lifetime_s  INT NOT NULL,                  -- seconds (e.g. 13 months in seconds)
  cookie_domain   TEXT,                          -- optional; defaults to request host
  path            TEXT NOT NULL DEFAULT '/',
  secure          BOOLEAN NOT NULL DEFAULT TRUE,
  http_only       BOOLEAN NOT NULL DEFAULT FALSE,
  same_site       TEXT NOT NULL DEFAULT 'Lax'
                  CHECK (same_site IN ('Lax','Strict','None')),
  is_active       BOOLEAN NOT NULL DEFAULT TRUE,
  last_used_at    TIMESTAMPTZ,
  hit_count       BIGINT NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(service_id, cookie_name)
);
CREATE INDEX idx_cookie_ext_service ON cookie_extensions(service_id);

CREATE TABLE cookie_extension_logs (
  id              BIGSERIAL PRIMARY KEY,
  cookie_ext_id   UUID NOT NULL REFERENCES cookie_extensions(id) ON DELETE CASCADE,
  ts              TIMESTAMPTZ NOT NULL DEFAULT now(),
  status_code     INT,
  source_ip       INET,
  user_agent      TEXT,
  bytes_in        INT,
  bytes_out       INT
);
CREATE INDEX idx_cookie_logs_ext ON cookie_extension_logs(cookie_ext_id, ts DESC);
```

### 15B.4 Routing

Add a Traefik router (per service) on the **edge** network:

```
Host(`abc123.edge.hostaffin.com`) && PathPrefix(`/cookie/`)
  → service sgtm_abc123 (port 8080)
  middlewares: stripPrefix(/cookie)
```

Inside the container, a Go sidecar (or the sGTM container's built-in client extension) handles:

- `GET  /extend` — list active cookie extensions (admin-only; auth via internal JWT).
- `POST /extend/set` — set a new extended cookie.
- `GET  /extend/get/:name` — read an extended cookie (server-side only; never exposed to JS).
- `POST /extend/proxy` — proxy a pixel/JS request to the original vendor with rewritten headers.

### 15B.5 Request Flow (Cookie Set)

```
Browser (customer.com)
  → GET https://customer.com/cookie/extend?_ga=GA1.2.123.456&...
Traefik
  → strips /cookie prefix
  → routes to sGTM container
Container
  → parses query, looks up cookie_name in cookie_extensions
  → issues Set-Cookie: _ga=GA1.2.123.456; Domain=customer.com;
                     Path=/; Max-Age=34190000; Secure; SameSite=Lax
  → 302 back to original page
```

### 15B.6 Request Flow (Cookie Proxy / Pixel)

```
Browser pixel request
  → https://customer.com/cookie/extend/fbp?...
Traefik → sGTM container
Container
  → matches cookie_name=_fbp
  → opens server-side HTTP to https://www.facebook.com/tr?id=...
  → returns 200 transparent GIF
  → sets first-party _fbp cookie (extended lifetime)
  → logs request in cookie_extension_logs
```

### 15B.7 Control Plane Endpoints

```
GET    /api/services/:id/cookie-extensions
POST   /api/services/:id/cookie-extensions        # add a new cookie extension
PUT    /api/cookie-extensions/:id                 # update lifetime/flags
DELETE /api/cookie-extensions/:id
POST   /api/cookie-extensions/:id/test            # simulate request
GET    /api/cookie-extensions/:id/analytics       # hit counts, status codes
GET    /api/services/:id/cookie-extension-logs    # recent log entries
```

### 15B.8 WHMCS Module Actions

Custom buttons in the WHMCS client area:
- `Add Cookie Extension` → opens a small form.
- `Test Extension` → opens a modal that runs a fake request and shows the resulting `Set-Cookie` header.
- `View Logs` → paginated recent requests (last 100).

### 15B.9 Quota Impact

- Each successful proxy/extend call counts as **1 request** toward the plan's `request_limit`.
- Bandwidth (in + out) counts toward `bandwidth_limit_gb`.
- Subject to same overage / suspend policy as sGTM traffic.

### 15B.10 Security & Privacy

- Endpoint is rate-limited: 600 req/min per IP, 60 req/min per cookie name per service.
- Container strips `Cookie` header from proxied vendor requests to prevent leakage of unrelated customer cookies.
- Logs are kept for **30 days** (configurable) — PII (IP, UA) is hashed in long-term storage.
- GDPR: customer can disable logging globally; default is to log a SHA-256 of (IP + daily salt) only.
- The `cookie/extend` endpoint is **not** advertised to search engines via `X-Robots-Tag: noindex`.

### 15B.11 Compatibility Matrix (v1)

| Vendor | Cookie | Supported? | Notes |
|---|---|---|---|
| Google Analytics 4 | `_ga`, `_ga_*` | ✅ | Default lifetime → 13 months |
| Universal Analytics | `_gid` | ✅ | 24h → 13 months |
| Meta Pixel | `_fbp`, `_fbc` | ✅ | 90 days → 13 months |
| TikTok Pixel | `_ttp` | ✅ | 13 months → 13 months |
| LinkedIn Insight | `li_sugr`, `AnalyticsSyncHistory` | ✅ | Server-side set |
| Microsoft Clarity | `_clck`, `_clsk` | ✅ | |
| Twitter/X Pixel | `muc_ads`, `personalization_id` | ✅ | |
| Pinterest | `_pinterest_ct_ua` | ✅ | |
| Snap Pixel | `_scid`, `sc_at` | ✅ | v1.1 |
| Generic (any first-party proxy) | any | ✅ | Manual config |

### 15B.12 Failure Modes

| Failure | Behavior |
|---|---|
| Vendor URL unreachable | Return 502 to browser; log; do NOT set extended cookie |
| Cookie name not registered | Return 404 with explanation |
| Lifetime exceeds 13 months (395 days for Chrome) | Clamp to 395 days, log warning |
| Container crash | Traefik 5xx; alert admin |
| Per-IP rate limit exceeded | Return 429; counted as 1 request unit |

### 15B.13 Testing Tool

The "Test Extension" feature in WHMCS:

1. Customer clicks button.
2. WHMCS module calls `POST /api/cookie-extensions/:id/test` with sample payload.
3. Control plane generates a synthetic request through the sGTM container.
4. Returns the response (status, headers, body) to a modal in the client area.
5. No real cookie is set on the customer's browser; the test runs server-to-server.

---

## 16. Authentication, Authorization, RBAC

### 16.1 Roles

| Role | Description |
|---|---|
| `super_admin` | Full access, can manage other admins, settings, plans |
| `admin` | Full access to services, nodes, plans (no user mgmt) |
| `support` | Read services, view logs, restart, verify domains |

### 16.2 Permissions Matrix

| Action | super_admin | admin | support |
|---|---|---|---|
| View services | ✅ | ✅ | ✅ |
| Restart service | ✅ | ✅ | ✅ |
| Suspend/Unsuspend | ✅ | ✅ | ❌ |
| Terminate | ✅ | ✅ | ❌ |
| Move node | ✅ | ✅ | ❌ |
| Edit plans | ✅ | ✅ | ❌ |
| Edit settings | ✅ | ❌ | ❌ |
| Manage users | ✅ | ❌ | ❌ |

### 16.3 JWT

- RS256, keys rotated every 90 days via `kid` header.
- Access token TTL: 15 min.
- Refresh token TTL: 7 days, stored as HttpOnly secure cookie.
- All endpoints validate `iss`, `aud`, `exp`.

### 16.4 API Keys for Node Agents

- Each node has a long-lived API key (rotated monthly) bound to a node UUID.
- Control plane's `POST /webhooks/nodes/:id/...` validates that the key matches the node and is not revoked.

---

## 17. Monitoring, Alerting, Observability

### 17.1 Metrics Sources

- Node Agent → control plane → ClickHouse.
- Traefik metrics endpoint → scraped by control plane.
- PostgreSQL slow query log via `pg_stat_statements`.

### 17.2 Alerts

| Trigger | Condition | Channel |
|---|---|---|
| Node offline | `last_heartbeat > 2 min` | Email + Telegram + Discord |
| SSL failed | `ssl_status = failed` for 10 min | Email + Discord |
| Container crash loop | `restart_count > 5 in 5 min` | Email + Telegram |
| High CPU | `cpu_pct > 90%` for 10 min | Email |
| High RAM | `ram_pct > 90%` for 10 min | Email |
| Quota exceeded | `requests > limit` | Email + Telegram |
| Disk pressure | `disk_used_pct > 85` | Email |

### 17.3 Notification Channels

- **Email**: SMTP via configurable provider (SendGrid, SES, Postmark).
- **Telegram**: Bot token + chat ID per environment.
- **Discord**: Webhook URL per environment.

All channels defined in `settings.alerting`.

### 17.4 Retention

- Detailed metrics (1s resolution) in ClickHouse: 7 days.
- 5-minute rollups: 90 days.
- Daily rollups in PostgreSQL: 13 months.
- Audit logs: 13 months.

---

## 18. Service Lifecycle State Machine

```
            ┌──────────┐
            │ pending  │
            └────┬─────┘
                 │ worker starts
                 ▼
            ┌──────────────┐
   fail ◄───┤ provisioning ├───► active
            └────┬─────────┘
                 │ error
                 ▼
            ┌──────────┐
            │ failed   │ ── admin retry ──► pending
            └──────────┘

   active ──admin/quota──► suspended
   suspended ──admin/payment──► active
   active/suspended ──admin/customer──► terminated
```

### 18.1 Transitions

| From | To | Trigger |
|---|---|---|
| pending | provisioning | Worker picks up |
| provisioning | active | Deploy success |
| provisioning | failed | Deploy error |
| failed | pending | Admin retry |
| active | suspended | Admin / quota |
| suspended | active | Admin / payment / quota reset |
| any | terminated | Customer cancellation / admin |

### 18.2 Side Effects

- `active`: ensure container running, Traefik router exists.
- `suspended`: `docker service scale` to 0 OR stop container; keep edge hostname for reactivation.
- `terminated`: delete container, free edge hostname (recyclable), audit log.
- `failed`: notify admin, allow retry button.

---

## 19. Quota & Overage Enforcement

### 19.1 Plan Limits

| Plan | Requests/mo | CPU | RAM |
|---|---|---|---|
| Starter | 500,000 | 0.5 vCPU | 512 MB |
| Growth | 2,000,000 | 1 vCPU | 1 GB |
| Agency | 10,000,000 | 2 vCPU | 2 GB |

### 19.2 Enforcement Modes (global setting)

#### Mode A — Strict (suspend)
- When `requests_this_month >= request_limit`:
  - Set `services.status = suspended`.
  - Container scaled to 0.
  - Customer email: "Quota reached. Upgrade or wait until reset."

#### Mode B — Overage (recommended)
- Container keeps running.
- Service flagged `overage=true`.
- Customer banner in WHMCS: "You're 12% over your plan limit. Upgrade recommended."
- v2 adds overage billing; v1 just tracks.

### 19.3 Counter Reset

- Counters reset on the 1st of each month based on service `created_at` (anniversary) OR calendar month. **Decision needed.** Default v1: calendar month (UTC).

### 19.4 Bandwidth

- Tracked in GB.
- Same enforcement logic, with separate per-plan `bandwidth_limit_gb`.

---

## 20. Billing & Plan Management

### 20.1 Plan Lifecycle

- Plans live in WHMCS as products.
- WHMCS module's `ConfigOptions` map WHMCS product IDs to internal `plans.slug`.
- When admin edits a plan, the change applies **only to new services** unless `apply_to_existing=true`.

### 20.2 Upgrade Flow

1. Customer upgrades in WHMCS (standard upgrade).
2. WHMCS module calls `ChangePackage` → Control Plane `POST /api/services/{id}/upgrade`.
3. Control Plane:
   - Updates `plan_id`.
   - Issues Docker service update with new CPU/RAM.
   - Logs audit event.

### 20.3 Downgrade Flow

- Same as upgrade. Container is restarted with new limits.
- Disk usage is not affected.

### 20.4 Invoicing

- Pure WHMCS-managed. No billing logic in Control Plane.

---

## 21. Background Workers & Queues

### 21.1 Queue System: Asynq (Redis)

Topics:
- `provision` — create container.
- `deprovision` — delete container.
- `restart` — restart container.
- `upgrade` — resize container.
- `domain.verify` — DNS check.
- `ssl.check` — periodic cert check.
- `quota.scan` — daily quota sweep.
- `usage.rollup` — daily rollup to PostgreSQL.
- `webhook.deliver` — outgoing webhooks.
- `alert.dispatch` — send notifications.
- `loader.rollup` — daily loader hit rollup to ClickHouse + `usage_daily`.
- `loader.regenerate` — rotate loader_id, refresh Traefik router, mark old inactive.
- `cookie_ext.rollup` — daily cookie extension hit rollup.
- `cookie_ext.log_purge` — purge cookie extension logs older than 30 days.

### 21.2 Scheduled Jobs

| Job | Cron | Purpose |
|---|---|---|
| `node.heartbeat_check` | every 1m | mark nodes offline |
| `domain.reverify` | every 5m | retry unverified domains |
| `ssl.renewal_check` | every 6h | mark renewing/failed |
| `quota.scan` | every 1h | enforce quota |
| `usage.rollup` | 00:05 daily | write to `usage_daily` |
| `cleanup.terminated` | 03:00 daily | purge old terminated |
| `loader.rollup` | 00:10 daily | roll up loader hit counts |
| `cookie_ext.log_purge` | 04:00 daily | purge cookie extension logs > 30 days |

### 21.3 Worker Concurrency

- 50 workers for fast jobs (`restart`).
- 5 workers for slow jobs (`provision`).
- Backoff: exponential, max 5 attempts, then dead-letter.

---

## 22. Security Model

### 22.1 Threat Surface

- WHMCS ↔ Control Plane (server-to-server, HMAC-signed).
- Node Agent ↔ Control Plane (server-to-server, JWT).
- Admin Panel ↔ Control Plane (browser, JWT cookie).
- Customer browser ↔ Traefik ↔ sGTM (TLS only).

### 22.2 Defenses

- mTLS optional between node agent and control plane.
- WAF in front of Admin Panel (Cloudflare or Traefik plugins).
- Rate limit: 60 req/min/IP on Admin Panel; 1000 req/min on customer endpoints.
- Argon2id for admin passwords.
- Secrets in env or HashiCorp Vault; never in repo.
- Container `read_only` FS, `no-new-privileges`.
- All actions audited; immutable log table.
- Quarterly key rotation.

### 22.3 Customer Isolation

- One container per customer, no shared process namespace.
- Linux user namespace per container (v2).
- Traefik routers are host-based; only the matching service sees the request.

### 22.4 Data Protection

- TLS 1.2+ everywhere.
- Encrypted backups of PostgreSQL (pgBackRest) and ClickHouse.
- GDPR: customer data export & delete endpoints.

---

## 23. CI/CD, Environments, Deployment Topology

### 23.1 Environments

| Env | Purpose | Hosted |
|---|---|---|
| local | Docker Compose | Developer |
| staging | E2E tests + previews | Single VM |
| production | Customer | Multi-VM (HA) |

### 23.2 Production Topology (suggested)

- 2× Control Plane (Go binary) behind a LB.
- 1× PostgreSQL primary + 1 replica (managed or self-hosted).
- 1× Redis (managed).
- 1× ClickHouse (1 shard, 2 replicas).
- 3× Swarm manager nodes (HA).
- N× Swarm worker nodes (scale).
- 2× Traefik nodes (active-active).

### 23.3 CI Pipelines

- `ci-control-plane.yml`:
  - `go vet`, `golangci-lint`, `go test ./...`, build, push image to GHCR.
- `ci-admin-panel.yml`:
  - `pnpm typecheck`, `lint`, `build`, deploy preview on PR.
- `ci-whmcs-module.yml`:
  - `php -l`, syntax tests.

### 23.4 Release

- Tag → GitHub Action builds images → pushes to GHCR.
- Ansible playbook pulls and runs on nodes.
- DB migrations run automatically on control plane start with a `migrate` job.

---

## 24. Development Milestones & Sprint Plan

> **Target v1 timeline:** 14–16 weeks, 2 engineers + 1 designer.

### Milestone 0 — Foundations (Week 1–2)
- Repo scaffold, monorepo, CI.
- Docker Compose for local dev (Postgres, Redis, ClickHouse, Traefik, MinIO for backups).
- Go module: config, logger, DB pool, Fiber app skeleton.
- DB migrations framework.

### Milestone 1 — Core Backend (Week 3–5)
- Auth (JWT, RBAC, login).
- Plans / Users / Nodes CRUD APIs.
- Repositories + tests.
- Webhook signing utilities.

### Milestone 2 — Provisioning Pipeline (Week 6–8)
- Node Agent MVP: deploy/delete/restart + heartbeat.
- Provisioner service + Asynq workers.
- Traefik + sample container test.
- Provisioning end-to-end.
- **Custom Loader bootstrap: generate `loader_id` on provision, mount `loader.js` route.**

### Milestone 3 — WHMCS Integration (Week 9–10)
- WHMCS module (Create/Suspend/Terminate/ChangePackage).
- Client area HTML panel rendering.
- **Loader & Cookie Extension cards in client area.**
- Webhook receiver.

### Milestone 4 — Domains & SSL (Week 11)
- Domain CRUD + DNS verification.
- Traefik dynamic labels.
- SSL status sync.
- **Cookie Extension routing (`/cookie/` prefix) per service.**

### Milestone 5 — Usage & Quotas (Week 12)
- ClickHouse schema + ingestion API.
- Daily rollup job.
- Quota engine (suspend vs. overage mode).
- **Loader hit metering & Cookie Extension request metering (counts toward quota).**

### Milestone 6 — Admin Panel (Week 13–14)
- Next.js scaffold + Shadcn.
- Dashboard, Services, Nodes, Plans, Users pages.
- **Loaders tab and Cookie Extensions tab in `/services/[id]`.**
- Charts.

### Milestone 7 — Hardening (Week 15–16)
- Alerting (email + Telegram + Discord).
- Audit log.
- Load test (k6) including Loader + Cookie Extension traffic.
- Security review (rate limit, SRI, lifetime clamp).
- Documentation.
- Production deploy.

---

## 25. Testing Strategy

### 25.1 Unit Tests
- Go: `go test ./...` (target 70%+ on `internal/services`).
- TypeScript: `vitest` for utility functions.

### 25.2 Integration Tests
- Postgres test container for repositories.
- Use `dockertest` Go library to spin up Redis, ClickHouse in tests.

### 25.3 End-to-End
- Local Docker Compose with full stack.
- WHMCS mock simulates module → control plane flow.
- Playwright e2e for Admin Panel.

### 25.4 Load Tests
- k6 simulates 1000 services with concurrent container deploys.
- Verify control plane and node agent under load.

### 25.5 Security Tests
- `trivy` image scans in CI.
- `gosec` for Go.
- `npm audit` for admin panel.
- Manual pen-test before v1 launch.

---

## 26. Risks, Open Questions, Decisions Needed

### 26.1 Open Questions

| # | Question | Default |
|---|---|---|
| Q1 | Quota counter reset: calendar month or service anniversary? | service anniversary |
| Q2 | Multi-manager Swarm HA or single-manager for v1? | Single manager + automated failover later |
| Q3 | Storage of customer GTM container config? | Use default `googletagmanager.com` static URL; allow override via env |
| Q4 | Pricing currency per region? | USD only v1 |
| Q5 | Backups: where & how often? | Daily pgBackRest to S3, 30d retention |
| Q6 | DDoS protection at edge? | Cloudflare proxy in front of Traefik (optional) |
| Q7 | Audit log immutability: append-only table or external sink? | Append-only in DB + weekly dump to S3 |
| Q8 | WHMCS email templates vs custom? | Use WHMCS templates; trigger from webhook events |
| Q9 | Loader: do loader hits count toward plan request quota? | Yes (1 hit = 1 request unit) |
| Q10 | Loader: do we ship a default template or fully empty? | Default template with editable trigger |
| Q11 | Cookie Extension: max number of cookie extensions per service? | 20 (configurable per plan) |
| Q12 | Cookie Extension: lifetime clamp — Chrome's 395-day cap? | Yes, hard clamp to 395 days |
| Q13 | Cookie Extension: which vendors to support in v1? | GA4, Meta, TikTok, LinkedIn, Clarity, Twitter/X, Pinterest |
| Q14 | Loader: rotation grace period (how long old id still works)? | 60 seconds |
| Q15 | Cookie Extension logs retention? | 30 days, then purge |

### 26.2 Risks

- **Docker Swarm maturity** vs Kubernetes — Swarm is simpler but has a smaller ecosystem. Mitigation: keep `node-agent` abstracted so we could swap runtimes later.
- **High-density containers** on a single node may cause noisy-neighbor CPU issues. Mitigation: hard cgroups limits, dedicated cores for hot plans (v2).
- **SSL issuance failures** (rate limits, DNS issues) — Traefik's default 5 ACME registrations/min could throttle. Mitigation: stagger new certs with a worker queue.
- **ClickHouse operational complexity** — keep monitoring Zookeeper or Keeper nodes carefully.
- **WHMCS API rate limits** during mass provisioning — batch webhook deliveries.

### 26.3 Decisions To Lock Before Sprint 1

1. JWT key rotation policy & storage (env vs Vault).
2. Plan IDs and WHMCS product mapping format.
3. Node naming convention (e.g., `edge-fra-01`).
4. Default DNS resolver for domain verification (`1.1.1.1`).
5. Default email provider for alerts.
6. Quota reset policy (Q1).
7. Logo, brand colors for admin panel.
8. Initial plan pricing & currency.

---

## 27. Appendix: API Reference, Configs, Snippets

### 27.1 Full API Reference (summary)

#### Auth
- `POST /api/auth/login` — `{email,password}` → `{access,refresh}`
- `POST /api/auth/refresh` — `{refresh}` → new pair
- `POST /api/auth/logout` — invalidates refresh

#### Services
- `POST /api/services` — admin/whmcs-only
- `GET /api/services` — filters: status, plan, node, search
- `GET /api/services/:id`
- `DELETE /api/services/:id`
- `POST /api/services/:id/restart`
- `POST /api/services/:id/suspend`
- `POST /api/services/:id/unsuspend`
- `POST /api/services/:id/upgrade` — `{plan_slug}`
- `POST /api/services/:id/move` — `{node_id}`
- `GET /api/services/:id/usage?from=&to=`
- `GET /api/services/:id/metrics?range=1h|24h|7d|30d`

#### Domains
- `POST /api/services/:id/domains` — `{domain}`
- `GET /api/services/:id/domains`
- `POST /api/domains/:id/verify`
- `DELETE /api/domains/:id`

#### Loaders (Custom Loader)
- `GET    /api/services/:id/loaders`
- `POST   /api/services/:id/loaders` — `{mode: "live"|"preview"}`
- `GET    /api/loaders/:loader_id`
- `PUT    /api/loaders/:loader_id/config` — `{trigger_type, trigger_value, respect_dnt, allow_bots}`
- `POST   /api/loaders/:loader_id/regenerate` — rotates id, old becomes inactive
- `POST   /api/loaders/:loader_id/disable`
- `GET    /api/loaders/:loader_id/analytics?range=24h|7d|30d`

#### Cookie Extensions
- `GET    /api/services/:id/cookie-extensions`
- `POST   /api/services/:id/cookie-extensions` — `{cookie_name, vendor_url, new_lifetime_s, cookie_domain?, path?, secure?, http_only?, same_site?}`
- `PUT    /api/cookie-extensions/:id`
- `DELETE /api/cookie-extensions/:id`
- `POST   /api/cookie-extensions/:id/test` — synthetic request, returns headers
- `GET    /api/cookie-extensions/:id/analytics?range=24h|7d|30d`
- `GET    /api/services/:id/cookie-extension-logs?limit=&offset=`

#### Plans
- `GET /api/plans`
- `POST /api/plans` (super_admin)
- `PUT /api/plans/:id`

#### Nodes
- `GET /api/nodes`
- `POST /api/nodes`
- `POST /api/nodes/:id/drain`
- `POST /api/nodes/:id/maintenance`
- `POST /api/nodes/:id/enable`

#### Users
- `GET /api/users`
- `POST /api/users`
- `PUT /api/users/:id`
- `DELETE /api/users/:id`

#### Settings
- `GET /api/settings`
- `PUT /api/settings`

#### Webhooks
- `POST /webhooks/whmcs` — incoming
- `POST /webhooks/nodes/:id/metrics` — incoming
- `POST /webhooks/nodes/:id/deploy-result` — incoming

#### Internal
- `POST /internal/ingest/metrics` — node agent ingestion

### 27.2 Environment Variables (control plane)

```
APP_ENV=production
HTTP_PORT=8080
DATABASE_URL=postgres://user:pass@host:5432/sgtm
REDIS_URL=redis://host:6379
CLICKHOUSE_URL=clickhouse://host:9000
JWT_PRIVATE_KEY_PEM=...
JWT_PUBLIC_KEY_PEM=...
NODE_AGENT_SHARED_SECRET=...
WHMCS_WEBHOOK_SECRET=...
TRAEFIK_API_URL=http://traefik:8080
SMTP_HOST=...
SMTP_PORT=587
SMTP_USER=...
SMTP_PASS=...
TELEGRAM_BOT_TOKEN=...
DISCORD_WEBHOOK_URL=...
LOG_LEVEL=info
```

### 27.3 Sample WHMCS Module ConfigOptions

```php
function hostaffin_sgtm_ConfigOptions() {
  return [
    "plan_slug" => [
      "FriendlyName" => "Plan",
      "Type"         => "dropdown",
      "Options"      => "starter,growth,agency",
      "Description"  => "Internal plan slug",
    ],
  ];
}
```

### 27.4 Sample Edge Hostname Generator

```go
func GenerateEdgeHostname() string {
  b := make([]byte, 8)
  rand.Read(b)
  return fmt.Sprintf("%s.edge.hostaffin.com", hex.EncodeToString(b))
}
```

### 27.5 Sample `docker-compose.yml` (Local)

```yaml
version: "3.9"
services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_PASSWORD: devpass
      POSTGRES_DB: sgtm
    ports: ["5432:5432"]
    volumes: ["pgdata:/var/lib/postgresql/data"]
  redis:
    image: redis:7
    ports: ["6379:6379"]
  clickhouse:
    image: clickhouse/clickhouse-server:24
    ports: ["9000:9000","8123:8123"]
    ulimits:
      nofile: { soft: 262144, hard: 262144 }
  traefik:
    image: traefik:v3
    command:
      - "--providers.docker.swarmMode=true"
      - "--entrypoints.web.address=:80"
    ports: ["80:80","443:443","8080:8080"]
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
  control-plane:
    build: ./control-plane
    environment:
      DATABASE_URL: postgres://postgres:devpass@postgres:5432/sgtm
      REDIS_URL: redis://redis:6379
      CLICKHOUSE_URL: clickhouse://clickhouse:9000
    ports: ["8090:8080"]
    depends_on: [postgres, redis, clickhouse]
  admin-panel:
    build: ./admin-panel
    ports: ["3000:3000"]
    environment:
      CONTROL_PLANE_URL: http://control-plane:8080
volumes:
  pgdata:
```

### 27.6 Sample `node-agent` systemd unit

```ini
[Unit]
Description=Hostaffin sGTM Node Agent
After=docker.service
Requires=docker.service

[Service]
ExecStart=/usr/local/bin/hostaffin-node-agent
Restart=always
RestartSec=5
Environment=CONTROL_PLANE_URL=https://control-plane.hostaffin.com
Environment=NODE_ID=edge-fra-01
Environment=NODE_API_KEY=...
EnvironmentFile=-/etc/hostaffin/node-agent.env

[Install]
WantedBy=multi-user.target
```

### 27.7 Glossary

- **sGTM** — Server-side Google Tag Manager.
- **WHMCS** — Web Host Manager Complete Solution (billing/automation platform).
- **Traefik** — Reverse proxy and load balancer.
- **ClickHouse** — Columnar OLAP database for analytics.
- **CAPI** — Meta Conversions API (future scope).
- **Edge hostname** — Auto-generated public hostname pointing to Traefik.
- **Node** — A physical or virtual host that runs sGTM containers.
- **Plan** — A resource tier mapped to a WHMCS product.
- **Custom Loader** — First-party gated JS snippet served from the customer's own domain, fed into sGTM.
- **Loader ID** — Unguessable per-service identifier (`lk_xxxxxxxx`) used as a key for the loader file.
- **Cookie Extension** — Endpoint on the customer's domain that sets/extends third-party tracking cookies as first-party cookies, with proxy support.
- **SRI** — Subresource Integrity hash for the loader script.
- **ITP / ETP** — Intelligent Tracking Prevention (Safari) / Enhanced Tracking Protection (Firefox).

---

## Sign-off Checklist (Before Sprint 1)

- [ ] PRD reviewed and approved.
- [ ] Tech stack approved.
- [ ] Brand assets provided (logo, color palette).
- [ ] WHMCS test instance available.
- [ ] Hosting infrastructure decision (self-hosted vs Hetzner/AWS).
- [ ] Initial plans and pricing confirmed.
- [ ] Quota reset policy (Q1) decided.
- [ ] Email/SMTP provider chosen.
- [ ] Alerting channels (Telegram/Discord) tokens ready.
- [ ] Domain registrar for `hostaffin.com` reviewed.
- [ ] ClickHouse hosted solution chosen.
- [ ] CI secrets configured.
- [ ] Custom Loader: default template approved (Q10).
- [ ] Custom Loader: rotation grace period decided (Q14).
- [ ] Cookie Extension: max extensions per service decided (Q11).
- [ ] Cookie Extension: lifetime clamp policy confirmed (Q12).
- [ ] Cookie Extension: vendor list for v1 finalized (Q13).
- [ ] Cookie Extension: log retention policy confirmed (Q15).
- [ ] Loader hit → request quota impact confirmed (Q9).

---

*End of Plan*
