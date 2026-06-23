-- 0001_init.up.sql
-- Hostaffin sGTM Platform — initial schema
-- PostgreSQL 16+

CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "citext";

-- ───────────────────────────────────────────────
-- Users (admins, support)
-- ───────────────────────────────────────────────
CREATE TABLE users (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email           CITEXT UNIQUE NOT NULL,
  password        TEXT NOT NULL,             -- argon2id hash
  role            TEXT NOT NULL CHECK (role IN ('super_admin','admin','support')),
  whmcs_client_id INT UNIQUE,                -- link to WHMCS client (optional)
  is_active       BOOLEAN NOT NULL DEFAULT TRUE,
  last_login_at   TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_users_role ON users(role);

-- ───────────────────────────────────────────────
-- Plans
-- ───────────────────────────────────────────────
CREATE TABLE plans (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  whmcs_product_id  INT UNIQUE NOT NULL,
  name              TEXT NOT NULL,
  slug              TEXT UNIQUE NOT NULL,
  cpu_limit         NUMERIC(4,2) NOT NULL,    -- vCPU
  ram_limit_mb      INT NOT NULL,
  request_limit     BIGINT NOT NULL,          -- monthly
  bandwidth_limit_gb INT NOT NULL,
  container_replicas INT NOT NULL DEFAULT 1,
  price_cents       INT NOT NULL,
  currency          CHAR(3) NOT NULL DEFAULT 'USD',
  is_active         BOOLEAN NOT NULL DEFAULT TRUE,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_plans_active ON plans(is_active);

-- ───────────────────────────────────────────────
-- Nodes
-- ───────────────────────────────────────────────
CREATE TABLE nodes (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  hostname        TEXT UNIQUE NOT NULL,
  region          TEXT,
  status          TEXT NOT NULL DEFAULT 'offline'
                  CHECK (status IN ('online','offline','draining','maintenance','disabled')),
  total_cpu       NUMERIC(4,2),
  total_ram_mb    INT,
  used_cpu        NUMERIC(4,2) DEFAULT 0,
  used_ram_mb     INT DEFAULT 0,
  container_count INT DEFAULT 0,
  last_heartbeat  TIMESTAMPTZ,
  agent_version   TEXT,
  is_edge         BOOLEAN NOT NULL DEFAULT TRUE,   -- runs Traefik
  api_key_hash    TEXT,                            -- bcrypt(node API key)
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_nodes_status ON nodes(status);

-- ───────────────────────────────────────────────
-- Services (sGTM containers)
-- ───────────────────────────────────────────────
CREATE TABLE services (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  whmcs_service_id  INT UNIQUE NOT NULL,
  whmcs_client_id   INT NOT NULL,
  plan_id           UUID NOT NULL REFERENCES plans(id),
  node_id           UUID REFERENCES nodes(id),
  container_id      TEXT,
  container_name    TEXT UNIQUE,
  status            TEXT NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending','provisioning','active','suspended',
                                      'terminated','failed')),
  edge_hostname     TEXT UNIQUE NOT NULL,
  failure_reason    TEXT,
  overage           BOOLEAN NOT NULL DEFAULT FALSE,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  activated_at      TIMESTAMPTZ,
  terminated_at     TIMESTAMPTZ
);
CREATE INDEX idx_services_status ON services(status);
CREATE INDEX idx_services_node ON services(node_id);
CREATE INDEX idx_services_whmcs_client ON services(whmcs_client_id);

-- ───────────────────────────────────────────────
-- Domains
-- ───────────────────────────────────────────────
CREATE TABLE domains (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_id        UUID NOT NULL REFERENCES services(id) ON DELETE CASCADE,
  domain            TEXT UNIQUE NOT NULL,
  is_primary        BOOLEAN NOT NULL DEFAULT FALSE,
  ssl_status        TEXT NOT NULL DEFAULT 'pending'
                    CHECK (ssl_status IN ('pending','issued','renewing','failed')),
  verified          BOOLEAN NOT NULL DEFAULT FALSE,
  verification_token TEXT NOT NULL,
  last_checked_at   TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_domains_service ON domains(service_id);

-- ───────────────────────────────────────────────
-- Daily usage rollups (Postgres)
-- ───────────────────────────────────────────────
CREATE TABLE usage_daily (
  service_id    UUID NOT NULL REFERENCES services(id) ON DELETE CASCADE,
  date          DATE NOT NULL,
  requests      BIGINT NOT NULL DEFAULT 0,
  bandwidth_b   BIGINT NOT NULL DEFAULT 0,
  loader_hits   BIGINT NOT NULL DEFAULT 0,
  cookie_ext_hits BIGINT NOT NULL DEFAULT 0,
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (service_id, date)
);
CREATE INDEX idx_usage_daily_date ON usage_daily(date DESC);

-- ───────────────────────────────────────────────
-- Audit logs
-- ───────────────────────────────────────────────
CREATE TABLE audit_logs (
  id          BIGSERIAL PRIMARY KEY,
  user_id     UUID REFERENCES users(id),
  actor_type  TEXT NOT NULL,                   -- 'admin','system','whmcs','node'
  action      TEXT NOT NULL,                   -- e.g. 'service.restart'
  resource    TEXT,                            -- e.g. 'service:uuid'
  metadata    JSONB,
  ip          INET,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_audit_action ON audit_logs(action);
CREATE INDEX idx_audit_created ON audit_logs(created_at DESC);

-- ───────────────────────────────────────────────
-- Webhooks outbox (outgoing)
-- ───────────────────────────────────────────────
CREATE TABLE webhooks_outbox (
  id          BIGSERIAL PRIMARY KEY,
  event       TEXT NOT NULL,
  target      TEXT NOT NULL,                    -- 'whmcs', 'discord', etc.
  payload     JSONB NOT NULL,
  delivered   BOOLEAN NOT NULL DEFAULT FALSE,
  attempts    INT NOT NULL DEFAULT 0,
  last_error  TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  delivered_at TIMESTAMPTZ
);
CREATE INDEX idx_outbox_pending ON webhooks_outbox(delivered, created_at);

-- ───────────────────────────────────────────────
-- Updated_at triggers
-- ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated_at      BEFORE UPDATE ON users      FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_plans_updated_at      BEFORE UPDATE ON plans      FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_services_updated_at   BEFORE UPDATE ON services   FOR EACH ROW EXECUTE FUNCTION set_updated_at();