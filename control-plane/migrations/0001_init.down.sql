-- 0001_init.down.sql

DROP TRIGGER IF EXISTS trg_services_updated_at ON services;
DROP TRIGGER IF EXISTS trg_plans_updated_at    ON plans;
DROP TRIGGER IF EXISTS trg_users_updated_at    ON users;
DROP FUNCTION IF EXISTS set_updated_at();

DROP TABLE IF EXISTS webhooks_outbox;
DROP TABLE IF EXISTS audit_logs;
DROP TABLE IF EXISTS usage_daily;
DROP TABLE IF EXISTS domains;
DROP TABLE IF EXISTS services;
DROP TABLE IF EXISTS nodes;
DROP TABLE IF EXISTS plans;
DROP TABLE IF EXISTS users;