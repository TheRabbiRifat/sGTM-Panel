-- 0002_loaders.up.sql
-- Custom Loader (gated JS snippet)

CREATE TABLE loaders (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_id    UUID NOT NULL REFERENCES services(id) ON DELETE CASCADE,
  loader_id     TEXT UNIQUE NOT NULL,                    -- "lk_xxxxxxxx"
  version       INT NOT NULL DEFAULT 1,
  mode          TEXT NOT NULL DEFAULT 'live'
                CHECK (mode IN ('live','preview')),
  is_active     BOOLEAN NOT NULL DEFAULT TRUE,
  hit_count     BIGINT NOT NULL DEFAULT 0,
  last_hit_at   TIMESTAMPTZ,
  sri_hash      TEXT,                                    -- subresource integrity
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  rotated_at    TIMESTAMPTZ
);
CREATE INDEX idx_loaders_service ON loaders(service_id);
CREATE INDEX idx_loaders_active  ON loaders(service_id, is_active);

CREATE TABLE loader_configs (
  loader_id     TEXT PRIMARY KEY REFERENCES loaders(loader_id) ON DELETE CASCADE,
  trigger_type  TEXT NOT NULL DEFAULT 'immediate'
                CHECK (trigger_type IN ('immediate','consent','delay','element')),
  trigger_value TEXT,                                     -- ms delay, CSS selector, or consent cookie name
  cookie_name   TEXT,
  respect_dnt   BOOLEAN NOT NULL DEFAULT TRUE,
  allow_bots    BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);