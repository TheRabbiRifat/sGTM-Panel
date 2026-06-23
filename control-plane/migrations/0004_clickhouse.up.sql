-- 0004_clickhouse.up.sql
-- Reference ClickHouse DDL — run manually with `clickhouse-client` after Postgres migrations.
-- Idempotent.

CREATE DATABASE IF NOT EXISTS sgtm;

CREATE TABLE IF NOT EXISTS sgtm.events_raw (
  ts          DateTime64(3),
  service_id  UUID,
  node_id     UUID,
  source      LowCardinality(String),     -- 'gtm','loader','cookie_ext'
  requests    UInt64,
  bytes_in    UInt64,
  bytes_out   UInt64,
  cpu_pct     Float32,
  ram_mb      UInt32,
  status_code UInt16
) ENGINE = MergeTree
PARTITION BY toYYYYMM(ts)
ORDER BY (service_id, source, ts);

CREATE TABLE IF NOT EXISTS sgtm.events_5m
AS sgtm.events_raw
ENGINE = SummingMergeTree
PARTITION BY toYYYYMM(ts)
ORDER BY (service_id, source, ts);

CREATE MATERIALIZED VIEW IF NOT EXISTS sgtm.events_5m_mv
TO sgtm.events_5m AS
SELECT
  toStartOfFiveMinute(ts) AS ts,
  service_id,
  source,
  sum(requests)   AS requests,
  sum(bytes_in)   AS bytes_in,
  sum(bytes_out)  AS bytes_out,
  avg(cpu_pct)    AS cpu_avg,
  avg(ram_mb)     AS ram_avg
FROM sgtm.events_raw
GROUP BY ts, service_id, source;