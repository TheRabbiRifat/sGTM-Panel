#!/usr/bin/env bash
# ─────────────────────────────────────────────
# rotate-jwt.sh — rotate the RS256 keypair used
# by the control plane. Run on a quiet moment;
# existing access tokens remain valid for at most
# JWT_ACCESS_TTL (default 15m).
# ─────────────────────────────────────────────
set -euo pipefail

cd "$(dirname "$0")/../.."

mkdir -p control-plane/keys
openssl genpkey -algorithm RSA -out control-plane/keys/private.new.pem -pkeyopt rsa_keygen_bits:2048 2>/dev/null
openssl rsa -in control-plane/keys/private.new.pem -pubout -out control-plane/keys/public.new.pem 2>/dev/null

mv control-plane/keys/private.new.pem control-plane/keys/private.pem
mv control-plane/keys/public.new.pem  control-plane/keys/public.pem

echo "▶ Restarting control-plane…"
docker compose restart control-plane
echo "✅ New keypair is live."