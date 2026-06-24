-- Reverse 0005_loader_alias_fbp
DROP INDEX IF EXISTS idx_loader_configs_fbp;
DROP INDEX IF EXISTS idx_loader_configs_fbc;

ALTER TABLE loader_configs
  DROP CONSTRAINT IF EXISTS chk_js_alias;

ALTER TABLE loader_configs
  DROP COLUMN IF EXISTS vendor_mapping,
  DROP COLUMN IF EXISTS honor_consent,
  DROP COLUMN IF EXISTS fbc_cookie_name,
  DROP COLUMN IF EXISTS fbp_cookie_name,
  DROP COLUMN IF EXISTS js_file_alias;
