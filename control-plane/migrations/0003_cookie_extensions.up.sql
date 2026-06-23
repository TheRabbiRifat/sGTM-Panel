-- 0003_cookie_extensions.up.sql
-- Cookie Extension feature

CREATE TABLE cookie_extensions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_id      UUID NOT NULL REFERENCES services(id) ON DELETE CASCADE,
  cookie_name     TEXT NOT NULL,
  vendor_url      TEXT NOT NULL,
  new_lifetime_s  INT NOT NULL,                            -- clamped to 34190000 (395d) on insert
  cookie_domain   TEXT,
  path            TEXT NOT NULL DEFAULT '/',
  secure          BOOLEAN NOT NULL DEFAULT TRUE,
  http_only       BOOLEAN NOT NULL DEFAULT FALSE,
  same_site       TEXT NOT NULL DEFAULT 'Lax'
                  CHECK (same_site IN ('Lax','Strict','None')),
  is_active       BOOLEAN NOT NULL DEFAULT TRUE,
  last_used_at    TIMESTAMPTZ,
  hit_count       BIGINT NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(service_id, cookie_name),
  CONSTRAINT chk_lifetime_chrome_cap CHECK (new_lifetime_s <= 34190000)
);
CREATE INDEX idx_cookie_ext_service ON cookie_extensions(service_id);

CREATE TRIGGER trg_cookie_ext_updated_at BEFORE UPDATE ON cookie_extensions
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE cookie_extension_logs (
  id              BIGSERIAL PRIMARY KEY,
  cookie_ext_id   UUID NOT NULL REFERENCES cookie_extensions(id) ON DELETE CASCADE,
  ts              TIMESTAMPTZ NOT NULL DEFAULT now(),
  status_code     INT,
  source_ip_hash  TEXT,                                    -- hashed IP for privacy
  user_agent      TEXT,
  bytes_in        INT,
  bytes_out       INT
);
CREATE INDEX idx_cookie_logs_ext ON cookie_extension_logs(cookie_ext_id, ts DESC);