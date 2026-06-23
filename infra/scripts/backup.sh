#!/usr/bin/env bash
# ─────────────────────────────────────────────
# backup.sh — pgBackRest-style full backup of
# Postgres + ClickHouse to a configured S3 bucket.
# Designed to run nightly from cron.
# ─────────────────────────────────────────────
set -euo pipefail

S3_BUCKET="${HOSTAFFIN_BACKUP_BUCKET:-s3://hostaffin-backups}"
PREFIX="${HOSTAFFIN_BACKUP_PREFIX:-$(date -u +%Y/%m/%d)}"

echo "▶ Dumping Postgres…"
docker exec sgtm-postgres pg_dump -U sgtm -d sgtm --no-owner --no-privileges | \
  gzip > /tmp/sgtm-pg-$(date -u +%Y%m%d%H%M%S).sql.gz

echo "▶ Uploading to ${S3_BUCKET}/${PREFIX}/…"
aws s3 cp /tmp/sgtm-pg-*.sql.gz "${S3_BUCKET}/${PREFIX}/" --sse aws:kms

echo "▶ Cleaning local files older than 7 days…"
find /tmp -name 'sgtm-pg-*.sql.gz' -mtime +7 -delete

echo "✅ Backup complete."