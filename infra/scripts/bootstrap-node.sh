#!/usr/bin/env bash
# ─────────────────────────────────────────────
# bootstrap-node.sh — quick local bootstrap
# Use this for spinning up a single-node Swarm
# for development. Production uses Ansible.
# ─────────────────────────────────────────────
set -euo pipefail

NODE_ID="${NODE_ID:-edge-local-01}"
CONTROL_PLANE_URL="${CONTROL_PLANE_URL:-http://localhost:8080}"
NODE_API_KEY="${NODE_API_KEY:-dev-node-key}"

echo "▶ Initialising Docker Swarm…"
docker swarm init --advertise-addr 127.0.0.1 || echo "Already in a swarm"

echo "▶ Creating overlay network hostaffin_edge…"
docker network create --driver overlay --attachable hostaffin_edge || true

echo "▶ Labelling this node as edge…"
docker node update --label-add hostaffin_role=edge "$(hostname)" || true

echo "▶ Installing node-agent…"
install -m 0755 ./node-agent/hostaffin-node-agent /usr/local/bin/hostaffin-node-agent || true

cat >/etc/hostaffin/node-agent.env <<EOF
CONTROL_PLANE_URL=${CONTROL_PLANE_URL}
NODE_ID=${NODE_ID}
NODE_API_KEY=${NODE_API_KEY}
HEARTBEAT_EVERY=15s
METRICS_EVERY=10s
LOG_LEVEL=debug
EOF

cp ./infra/systemd/hostaffin-node-agent.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now hostaffin-node-agent || true

echo "✅ Done. node-agent should be reporting to ${CONTROL_PLANE_URL}."