-- ───────────────────────────────────────────────
-- Loader config: add JS-file alias + FBP / FBC cookie names
-- Lets clients rename gtm.js → trk-ss.js (or anything) and tell
-- the loader which cookies hold Facebook Pixel / Click IDs.
-- ───────────────────────────────────────────────
ALTER TABLE loader_configs
  ADD COLUMN js_file_alias    TEXT NOT NULL DEFAULT 'gtm.js',
  ADD COLUMN fbp_cookie_name  TEXT NOT NULL DEFAULT '_fbp',
  ADD COLUMN fbc_cookie_name  TEXT NOT NULL DEFAULT '_fbc',
  ADD COLUMN honor_consent    BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN vendor_mapping   JSONB NOT NULL DEFAULT '{}'::jsonb;

-- A sane allow-list of common aliases
ALTER TABLE loader_configs
  ADD CONSTRAINT chk_js_alias CHECK (
    js_file_alias IN (
      'gtm.js', 'gtag.js', 'analytics.js', 'trk.js', 'trk-ss.js',
      'fbevents.js', 'pixel.js', 'loader.js', 'custom'
    )
  );

-- Helpful index for analytics queries on FB cookies
CREATE INDEX idx_loader_configs_fbp ON loader_configs(fbp_cookie_name);
CREATE INDEX idx_loader_configs_fbc ON loader_configs(fbc_cookie_name);
