#!/usr/bin/env bash
# ───────────────────────────────────────────────────────────────────────
# Hostaffin sGTM Hosting Platform — Installer for YUM-family distros
# ───────────────────────────────────────────────────────────────────────
# This script provisions a fresh YUM-based host (Alma / Rocky / RHEL /
# CentOS / Oracle / Fedora / Amazon Linux) with everything needed to
# run the Hostaffin sGTM Platform:
#
#   ✓ System updates + EPEL
#   ✓ Firewalld rules (80, 443, 8080, 9000, 8123, 5432, 6379, 3000)
#   ✓ SELinux adjustments (when present)
#   ✓ Docker Engine + Compose plugin
#   ✓ Docker Swarm init (or join)
#   ✓ Overlay network hostaffin_edge
#   ✓ Node label hostaffin_role=master
#   ✓ Node Agent (systemd)
#   ✓ Traefik reverse proxy (systemd, host-network)
#   ✓ Project workspace under /opt/hostaffin
#   ✓ Control Plane + Admin Panel builds (or pulls from GHCR)
#   ✓ PostgreSQL + Redis + ClickHouse (via docker compose)
#   ✓ Migrations + seed
#   ✓ Health checks
#
# Modes:
#   --mode local          Single-host all-in-one (default for dev)
#   --mode master         Master node (Traefik + node-agent, joins swarm)
#   --mode controlplane   Control plane + DB stack only (no Traefik/node-agent)
#
# Every node in the cluster is a master node — there is no separate
# "edge" or "slave" role. Any node can run Traefik and serve customers.
#
# Supported distros (any YUM-based system with dnf or yum):
#   • AlmaLinux 8 / 9
#   • Rocky Linux 8 / 9
#   • RHEL 8 / 9
#   • CentOS Stream 8 / 9
#   • Oracle Linux 8 / 9
#   • Fedora 36+
#   • Amazon Linux 2 (yum) and Amazon Linux 2023 (dnf)
#
# Usage:
#   sudo ./install-yum.sh [--mode MODE] [--join-token TOKEN]
#                         [--manager-addr ADDR] [--control-plane-url URL]
#                         [--node-id ID] [--node-api-key KEY]
#                         [--github-token TOKEN] [--non-interactive]
#                         [--skip-firewall] [--skip-swap-disable]
#                         [--project-dir DIR]
#
# Environment overrides (same names, uppercase, with HOSTAFFIN_ prefix):
#   HOSTAFFIN_MODE, HOSTAFFIN_JOIN_TOKEN, HOSTAFFIN_MANAGER_ADDR,
#   HOSTAFFIN_CONTROL_PLANE_URL, HOSTAFFIN_NODE_ID, HOSTAFFIN_NODE_API_KEY,
#   HOSTAFFIN_PM=dnf|yum (force a specific package manager)
#
# Exit codes:
#   0  success
#   1  generic failure
#   2  invalid arguments
#   3  not running as root
#   4  unsupported OS
#   5  user aborted
# ───────────────────────────────────────────────────────────────────────

set -euo pipefail
IFS=$'\n\t'

# Handle --help BEFORE sourcing lib-pm.sh. We want --help to work even on
# hosts that don't have dnf or yum installed (e.g. an operator reading
# the docs on their laptop).
for _arg in "$@"; do
  if [[ "$_arg" == "-h" || "$_arg" == "--help" ]]; then
    awk '
      /^# ─/{ i++; next }
      i==2 { sub(/^# ?/, ""); print }
      i>=3 { exit }
    ' "$0"
    exit 0
  fi
done

# Pull in the shared package-manager helpers (auto-detects dnf vs yum).
# Resolve the script's directory even when run via `curl ... | sudo bash -s --`,
# where BASH_SOURCE[0] is unset because bash is reading the script from stdin.
SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" 2>/dev/null && pwd || true)"
if [[ -z "$SCRIPT_DIR" || ! -f "$SCRIPT_DIR/lib-pm.sh" ]]; then
  # Fallback: pull lib-pm.sh from the same GitHub source we came from.
  SCRIPT_URL="${HOSTAFFIN_INSTALL_URL:-https://raw.githubusercontent.com/TheRabbiRifat/sGTM-Panel/main/infra/scripts}"
  TMP_LIB_DIR="$(mktemp -d)"
  printf '\033[1;34m[install]\033[0m %s\n' "Downloading lib-pm.sh from $SCRIPT_URL ..." >&2
  if curl -fsSL "$SCRIPT_URL/lib-pm.sh" -o "$TMP_LIB_DIR/lib-pm.sh"; then
    SCRIPT_DIR="$TMP_LIB_DIR"
  else
    printf '\033[1;31m[err  ]\033[0m %s\n' "cannot locate lib-pm.sh (tried '$SCRIPT_DIR' and $SCRIPT_URL)" >&2
    exit 1
  fi
fi
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib-pm.sh"

# ───────────────────────────── Defaults ─────────────────────────────────
MODE="${HOSTAFFIN_MODE:-local}"
JOIN_TOKEN="${HOSTAFFIN_JOIN_TOKEN:-}"
MANAGER_ADDR="${HOSTAFFIN_MANAGER_ADDR:-}"
CONTROL_PLANE_URL="${HOSTAFFIN_CONTROL_PLANE_URL:-}"
NODE_ID="${HOSTAFFIN_NODE_ID:-}"
NODE_API_KEY="${HOSTAFFIN_NODE_API_KEY:-}"
GITHUB_TOKEN="${HOSTAFFIN_GITHUB_TOKEN:-}"
NON_INTERACTIVE=false
SKIP_FIREWALL=false
SKIP_SWAP=false
PROJECT_DIR="/opt/hostaffin"
LOG_DIR="/var/log/hostaffin"
ENV_FILE="/etc/hostaffin/hostaffin.env"
ADMIN_PWD_FILE="/root/.hostaffin-admin-password"
GHCR_IMAGE_BASE="${HOSTAFFIN_GHCR_IMAGE_BASE:-ghcr.io/hostaffin}"
DOCKER_VERSION="26.1.3"
GOLANG_VERSION="1.22.5"
NODE_VERSION="20"

# ──────────────────────────── Logging helpers ───────────────────────────
log()  { printf '\033[1;34m[install]\033[0m %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m[ ok  ]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[warn ]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[err  ]\033[0m %s\n' "$*" >&2; }
hr()   { printf '\n\033[1;36m%s\033[0m\n' "──────────────────────────────────────────────────────────────" >&2; }

# ─────────────────────────── Argument parsing ───────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)              MODE="$2"; shift 2 ;;
    --join-token)        JOIN_TOKEN="$2"; shift 2 ;;
    --manager-addr)      MANAGER_ADDR="$2"; shift 2 ;;
    --control-plane-url) CONTROL_PLANE_URL="$2"; shift 2 ;;
    --node-id)           NODE_ID="$2"; shift 2 ;;
    --node-api-key)      NODE_API_KEY="$2"; shift 2 ;;
    --github-token)      GITHUB_TOKEN="$2"; shift 2 ;;
    --project-dir)       PROJECT_DIR="$2"; shift 2 ;;
    --non-interactive)   NON_INTERACTIVE=true; shift ;;
    --skip-firewall)     SKIP_FIREWALL=true; shift ;;
    --skip-swap-disable) SKIP_SWAP=true; shift ;;
    -h|--help)           exit 0 ;;  # handled before script body
    *) err "Unknown argument: $1"; exit 2 ;;
  esac
done

# Validate mode early so we can fail fast on typos.
case "$MODE" in
  local|master|controlplane) ;;
  *) err "Invalid --mode '$MODE'. Must be one of: local, master, controlplane."; exit 2 ;;
esac

# Master mode requires the swarm join coordinates up-front.
if [[ "$MODE" == "master" ]]; then
  if [[ -z "$JOIN_TOKEN" || -z "$MANAGER_ADDR" ]]; then
    err "--mode master requires both --join-token and --manager-addr."
    exit 2
  fi
fi

# ─────────────────────── Initialise logging sink ───────────────────────
# Done after arg parsing so --help prints to the terminal cleanly.
mkdir -p "$LOG_DIR" 2>/dev/null || true
LOG_FILE="$LOG_DIR/install-$(date -u +%Y%m%d%H%M%S).log"
if [[ -w "$LOG_DIR" ]]; then
  exec > >(tee -a "$LOG_FILE") 2>&1
fi

# ───────────────────────────── Pre-flight ───────────────────────────────
require_root() {
  if [[ $EUID -ne 0 ]]; then
    err "This script must be run as root. Try: sudo $0"
    exit 3
  fi
}

require_yum_distro() {
  if [[ ! -f /etc/os-release ]]; then
    err "Cannot detect /etc/os-release"
    exit 4
  fi
  # shellcheck disable=SC1091  # /etc/os-release is provided by systemd at runtime
  . /etc/os-release

  # Accept any YUM-family distro: Alma / Rocky / RHEL / CentOS Stream /
  # Oracle / Fedora / Amazon Linux (both v2 and v2023). Reject anything
  # apt/deb-based or musl-based; the rest of the script depends on RPM.
  local id="${ID:-}"
  local id_like="${ID_LIKE:-}"
  local is_yum=0
  case "$id" in
    almalinux|rocky|rhel|centos|fedora|ol|amzn) is_yum=1 ;;
  esac
  if [[ "$id_like" == *"rhel"* || "$id_like" == *"centos"* || "$id_like" == *"fedora"* ]]; then
    is_yum=1
  fi

  if [[ $is_yum -eq 0 ]]; then
    err "This installer requires a YUM-family distro (dnf or yum)."
    err "Detected: ${id:-unknown} ${VERSION_ID:-} (id_like='${id_like:-}')."
    err "Re-run on AlmaLinux / Rocky / RHEL / CentOS Stream / Oracle / Fedora / Amazon Linux,"
    err "or fork the script for your distro."
    exit 4
  fi

  # We need *some* working PM. lib-pm.sh detects this, but if both dnf and
  # yum are missing (e.g. minimal container) we fail fast with a clear msg.
  pm_detect || { err "Neither dnf nor yum found in PATH"; exit 4; }
  log "Detected YUM-family distro: $PRETTY_NAME (using $PM_GLOBAL)"
}

confirm() {
  if $NON_INTERACTIVE; then return 0; fi
  local prompt="$1"
  local default="${2:-y}"
  local ans
  read -rp "$(printf '\033[1;33m[?]\033[0m %s [%s]: ' "$prompt" "$default")" ans
  ans="${ans:-$default}"
  case "${ans,,}" in
    y|yes) return 0 ;;
    *)     return 1 ;;
  esac
}

# ─────────────────────────── Package management ─────────────────────────
install_packages() {
  hr; log "Installing base packages…"
  pm_install \
    curl wget tar gzip ca-certificates \
    yum-utils epel-release \
    git make jq openssl \
    firewalld policycoreutils-python-utils \
    rsync htop bind-utils \
    || { err "$PM_GLOBAL install failed"; exit 1; }
  ok "Base packages installed"
}

# ─────────────────────────── System tuning ──────────────────────────────
tune_system() {
  hr; log "Tuning system…"
  # Disable swap (recommended for container hosts)
  if ! $SKIP_SWAP; then
    if swapon --show | grep -q .; then
      log "Disabling swap…"
      swapoff -a
      sed -i.bak '/\bswap\b/d' /etc/fstab
    fi
  fi
  # Sysctl for high-concurrency container host
  cat >/etc/sysctl.d/99-hostaffin.conf <<'EOF'
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65535
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
vm.max_map_count = 262144
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
EOF
  sysctl --system >/dev/null
  # ulimits for root
  cat >/etc/security/limits.d/99-hostaffin.conf <<'EOF'
* soft nofile 65535
* hard nofile 65535
* soft nproc  65535
* hard nproc  65535
root soft nofile 65535
root hard nofile 65535
root soft nproc  65535
root hard nproc  65535
EOF
  ok "System tuned"
}

# ───────────────────────────── Firewalld ────────────────────────────────
configure_firewalld() {
  if $SKIP_FIREWALL; then
    warn "Skipping firewall (per --skip-firewall)"
    return 0
  fi
  hr; log "Configuring firewalld…"
  systemctl enable --now firewalld
  # Always allow SSH (don't lock ourselves out)
  firewall-cmd --permanent --add-service=ssh >/dev/null
  # Public web
  firewall-cmd --permanent --add-service=http  >/dev/null
  firewall-cmd --permanent --add-service=https >/dev/null
  # Inter-service (loopback or trusted)
  firewall-cmd --permanent --add-port=2377/tcp  >/dev/null  # swarm mgmt
  firewall-cmd --permanent --add-port=7946/tcp  >/dev/null  # gossip
  firewall-cmd --permanent --add-port=7946/udp  >/dev/null
  firewall-cmd --permanent --add-port=4789/udp  >/dev/null  # vxlan
  # Control plane API + admin UI + node-agent exporter
  firewall-cmd --permanent --add-port=8080/tcp  >/dev/null
  firewall-cmd --permanent --add-port=3000/tcp  >/dev/null
  firewall-cmd --permanent --add-port=9100/tcp  >/dev/null
  # ClickHouse (in case of local install)
  firewall-cmd --permanent --add-port=8123/tcp  >/dev/null
  firewall-cmd --permanent --add-port=9000/tcp  >/dev/null
  firewall-cmd --reload
  ok "Firewall rules applied"
}

# ─────────────────────────────── Docker ─────────────────────────────────
install_docker() {
  hr; log "Installing Docker Engine ${DOCKER_VERSION}…"
  if command -v docker >/dev/null && docker --version | grep -q "Docker version"; then
    local cur
    cur="$(docker --version | awk '{print $3}' | tr -d ',')"
    if [[ "$cur" == "$DOCKER_VERSION" ]]; then
      ok "Docker ${DOCKER_VERSION} already installed"
    else
      warn "Existing Docker version ${cur}; will leave in place"
    fi
  else
    pm_remove docker docker-client docker-client-latest docker-common \
      docker-latest docker-latest-logrotate docker-engine podman runc 2>/dev/null || true
    pm_install dnf-plugins-core yum-utils >/dev/null 2>&1 || true
    pm_addrepo https://download.docker.com/linux/centos/docker-ce.repo
    pm_install \
      "docker-ce-${DOCKER_VERSION}" \
      "docker-ce-cli-${DOCKER_VERSION}" \
      containerd.io \
      docker-buildx-plugin \
      docker-compose-plugin
  fi
  systemctl enable --now docker
  systemctl is-active --quiet docker || { err "Docker failed to start"; exit 1; }
  ok "Docker is running"
}

install_docker_completion() {
  curl -fsSL https://raw.githubusercontent.com/docker/compose/v2.27.1/contrib/completion/bash/docker-compose \
    -o /etc/bash_completion.d/docker-compose 2>/dev/null || true
}

# ───────────────────────────── Swarm init/join ──────────────────────────
ensure_swarm() {
  hr; log "Configuring Docker Swarm…"
  if docker info 2>/dev/null | grep -q "Swarm: active"; then
    ok "Already in a Swarm"
    return 0
  fi
  case "$MODE" in
    local|controlplane)
      log "Initialising Swarm (manager)…"
      local advertise
      advertise=$(hostname -I 2>/dev/null | awk '{print $1}')
      [[ -z "$advertise" ]] && advertise="127.0.0.1"
      if ! docker swarm init --advertise-addr "$advertise" 2>/dev/null; then
        warn "swarm init with $advertise failed; retrying on 127.0.0.1"
        docker swarm init --advertise-addr 127.0.0.1
      fi
      ok "Swarm initialised as manager (advertise $advertise)"
      ;;
    master)
      # Validation already happened up-front; values are guaranteed here.
      log "Joining Swarm at ${MANAGER_ADDR}…"
      docker swarm join --token "$JOIN_TOKEN" "$MANAGER_ADDR" 2377
      ok "Joined swarm"
      ;;
  esac
}

label_node_master() {
  # Every node is a master node — no edge/slave distinction.
  if [[ "$MODE" != "master" && "$MODE" != "local" ]]; then
    return 0
  fi
  log "Labelling node as master…"
  # Wait for the node to appear in `docker node ls` (swarm convergence).
  local self=""
  local i=0
  while [[ $i -lt 30 ]]; do
    self=$(docker node ls --format '{{.Self}} {{.ID}}' 2>/dev/null \
           | awk '$1=="true"{print $2; exit}')
    [[ -n "$self" ]] && break
    sleep 1
    i=$((i + 1))
  done
  if [[ -z "$self" ]]; then
    warn "Could not determine self node id after 30s; falling back to hostname"
    self=$(hostname)
  fi
  if docker node update --label-add hostaffin_role=master "$self"; then
    ok "Node labelled"
  else
    warn "Could not label node (acceptable in single-node mode)"
  fi
}

create_overlay_network() {
  hr; log "Creating overlay network hostaffin_edge…"
  if docker network ls --format '{{.Name}}' 2>/dev/null | grep -qx 'hostaffin_edge'; then
    ok "Network already exists"
  else
    docker network create --driver overlay --attachable hostaffin_edge
    ok "Network created"
  fi
}

# ───────────────────────────── SELinux ──────────────────────────────────
configure_selinux() {
  if ! command -v getenforce >/dev/null; then
    log "SELinux not installed; skipping"
    return 0
  fi
  if [[ "$(getenforce)" != "Enforcing" ]]; then
    warn "SELinux is not enforcing; skipping"
    return 0
  fi
  hr; log "Adjusting SELinux for Docker/Traefik…"
  setsebool -P container_manage_cgroup 1 || true
  setsebool -P domain_can_mmap_files 1 || true
  mkdir -p /etc/systemd/system/traefik.service.d
  cat >/etc/systemd/system/traefik.service.d/override.conf <<'EOF' 2>/dev/null || true
[Service]
NoNewPrivileges=no
EOF
  # Custom module so traefik can write /letsencrypt + acme.json
  if ! semodule -l 2>/dev/null | grep -qx 'hostaffin'; then
    cat >/tmp/hostaffin.pp <<'EOF'
module hostaffin 1.0;
require {
  type unconfined_service_t;
  type etc_t;
  type var_log_t;
  type container_file_t;
  class file { create open read write getattr setattr unlink append rename };
  class dir { add_name create open read write getattr setattr remove_name rmdir search };
}
allow unconfined_service_t etc_t:file { create open read write getattr setattr unlink append rename };
allow unconfined_service_t var_log_t:dir { add_name create open read write getattr setattr remove_name rmdir search };
allow unconfined_service_t container_file_t:dir { add_name create open read write getattr setattr remove_name rmdir search };
EOF
    checkmodule -M -m -o /tmp/hostaffin.mod /tmp/hostaffin.pp 2>/dev/null || true
    semodule_package -o /tmp/hostaffin.pp /tmp/hostaffin.mod 2>/dev/null || true
    semodule -i /tmp/hostaffin.pp 2>/dev/null || true
  fi
  ok "SELinux adjusted"
}

# ─────────────────────────── Project layout ─────────────────────────────
prepare_project() {
  hr; log "Preparing project workspace at $PROJECT_DIR…"
  mkdir -p "$PROJECT_DIR" "$PROJECT_DIR/traefik" "$PROJECT_DIR/control-plane/keys"
  mkdir -p /etc/hostaffin
  # Allow hostaffin service user to write env
  chmod 750 /etc/hostaffin
  ok "Workspace prepared"
}

write_env() {
  hr; log "Writing environment file $ENV_FILE…"
  # Auto-generate a strong JWT keypair if missing
  if [[ ! -f "$PROJECT_DIR/control-plane/keys/private.pem" ]]; then
    openssl genpkey -algorithm RSA -out "$PROJECT_DIR/control-plane/keys/private.pem" \
      -pkeyopt rsa_keygen_bits:2048 2>/dev/null
    openssl rsa -in "$PROJECT_DIR/control-plane/keys/private.pem" -pubout \
      -out "$PROJECT_DIR/control-plane/keys/public.pem" 2>/dev/null
  fi
  # Build /etc/hostaffin/hostaffin.env
  local admin_pwd="${HOSTAFFIN_ADMIN_PASSWORD:-$(openssl rand -base64 18 | tr -d '=+/')}"
  local node_secret="${NODE_API_KEY:-$(openssl rand -hex 24)}"
  if [[ -z "$NODE_ID" ]]; then
    NODE_ID="master-$(hostname -s | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')-01"
  fi

  # Write the env file with placeholders for the multi-line PEM blocks.
  # We splice them in afterwards to keep them safely single-line in shell syntax.
  cat >"$ENV_FILE" <<EOF
# Hostaffin sGTM Platform — environment
# Generated by installer on $(date -u +%Y-%m-%dT%H:%M:%SZ)
APP_ENV=production
HTTP_PORT=8080
LOG_LEVEL=info
BASE_URL=${CONTROL_PLANE_URL:-http://localhost:8080}

DATABASE_URL=postgres://sgtm:sgtm@postgres:5432/sgtm?sslmode=disable
DB_MAX_OPEN=25
DB_MAX_IDLE=5

REDIS_URL=redis://redis:6379/0
CLICKHOUSE_URL=clickhouse://clickhouse:9000
CLICKHOUSE_DB=sgtm

JWT_PRIVATE_KEY_PEM=__JWT_PRIVATE_KEY_PEM__
JWT_PUBLIC_KEY_PEM=__JWT_PUBLIC_KEY_PEM__
JWT_ACCESS_TTL=15m
JWT_REFRESH_TTL=168h

NODE_AGENT_SHARED_SECRET=change-me-please
NODE_ID=$NODE_ID
NODE_API_KEY=$node_secret
CONTROL_PLANE_URL=${CONTROL_PLANE_URL:-http://localhost:8080}

EDGE_DOMAIN=edge.hostaffin.local

ADMIN_BOOTSTRAP_EMAIL=admin@hostaffin.local
ADMIN_BOOTSTRAP_PASSWORD=$admin_pwd

# If a GHCR token was provided, use it; otherwise the runtime pulls anonymous.
GITHUB_TOKEN=$GITHUB_TOKEN
EOF

  # Build the inline PEM block. We wrap it in a single shell-quoted line that
  # contains literal "\n" sequences; the runtime (Go's env reader) decodes
  # those back to real newlines. Doing it this way keeps the env file valid
  # shell syntax without multi-line quoting headaches.
  {
    printf 'JWT_PRIVATE_KEY_PEM="'
    printf '%s\\n' '-----BEGIN RSA PRIVATE KEY-----'
    # strip existing newlines if any, then re-emit
    tr -d '\n' < "$PROJECT_DIR/control-plane/keys/private.pem" \
      | fold -w 64 \
      | sed 's/.*/&\\n/'
    printf '%s\\n' '-----END RSA PRIVATE KEY-----'
    printf '"\n'
    printf 'JWT_PUBLIC_KEY_PEM="'
    printf '%s\\n' '-----BEGIN PUBLIC KEY-----'
    tr -d '\n' < "$PROJECT_DIR/control-plane/keys/public.pem" \
      | fold -w 64 \
      | sed 's/.*/&\\n/'
    printf '%s\\n' '-----END PUBLIC KEY-----'
    printf '"\n'
  } > "$ENV_FILE.pems"

  # Splice the PEM block in by replacing the placeholders we wrote above.
  # Prefer python3 (handles multi-char newlines safely); fall back to awk.
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$ENV_FILE" "$ENV_FILE.pems" <<'PYEOF'
import sys, pathlib
env, pems = sys.argv[1], sys.argv[2]
pem_text = pathlib.Path(pems).read_text()
text = pathlib.Path(env).read_text()
text = text.replace("__JWT_PRIVATE_KEY_PEM__", "").replace("__JWT_PUBLIC_KEY_PEM__", "")
# Insert the PEM block before the JWT_ACCESS_TTL line so the file stays tidy.
needle = "JWT_ACCESS_TTL=15m\n"
text = text.replace(needle, pem_text + needle, 1)
pathlib.Path(env).write_text(text)
PYEOF
  else
    awk -v pems="$ENV_FILE.pems" '
      /__JWT_PRIVATE_KEY_PEM__/ { while ((getline line < pems) > 0) print line; next }
      /__JWT_PUBLIC_KEY_PEM__/  { while ((getline line < pems) > 0) print line; next }
      { print }
    ' "$ENV_FILE" > "$ENV_FILE.tmp" && mv "$ENV_FILE.tmp" "$ENV_FILE"
  fi
  rm -f "$ENV_FILE.pems"

  # Final sanity: there must be no remaining placeholder.
  if grep -q '__JWT_' "$ENV_FILE" 2>/dev/null; then
    err "Failed to inline JWT keys into $ENV_FILE — placeholders remain."
    err "Check that python3 is installed, or fix the awk splice above."
    exit 1
  fi

  chmod 0640 "$ENV_FILE"
  ok "Environment written to $ENV_FILE"
  # Print the password ONLY to the terminal, never to the log file.
  if [[ -t 2 ]]; then
    printf '\n\033[1;33m[warn]\033[0m Admin password: \033[1m%s\033[0m  (save it now!)\n' "$admin_pwd" >&2
  fi
  printf '%s' "$admin_pwd" > "$ADMIN_PWD_FILE"
  chmod 0600 "$ADMIN_PWD_FILE"
}

# ─────────────────────────── Traefik (master mode) ────────────────────────
install_traefik_systemd() {
  if [[ "$MODE" != "master" && "$MODE" != "local" ]]; then return 0; fi
  hr; log "Installing Traefik reverse proxy…"
  mkdir -p /etc/traefik
  cat >/etc/traefik/traefik.yml <<EOF
api:
  dashboard: true
  insecure: false
log:
  level: INFO
  format: json
entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"
providers:
  docker:
    swarmMode: true
    exposedByDefault: false
    network: hostaffin_edge
certificatesResolvers:
  letsencrypt:
    acme:
      email: ops@hostaffin.com
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web
EOF
  mkdir -p /var/log/traefik /letsencrypt
  chmod 700 /letsencrypt
  # Run Traefik as a host-network container so it can bind 80/443 directly
  cat >/etc/systemd/system/hostaffin-traefik.service <<EOF
[Unit]
Description=Hostaffin Traefik (host network)
After=docker.service
Requires=docker.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=-/usr/bin/docker rm -f hostaffin-traefik
ExecStart=/usr/bin/docker run --rm --name hostaffin-traefik \\
  --network host \\
  -v /var/run/docker.sock:/var/run/docker.sock:ro \\
  -v /etc/traefik/traefik.yml:/etc/traefik/traefik.yml:ro \\
  -v /letsencrypt:/letsencrypt \\
  -v /var/log/traefik:/var/log/traefik \\
  traefik:v3.0
ExecStop=/usr/bin/docker stop hostaffin-traefik
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now hostaffin-traefik
  ok "Traefik installed and running"
}

# ─────────────────────────── Node agent ─────────────────────────────────
install_node_agent_systemd() {
  hr; log "Installing Node Agent…"
  if [[ ! -x /usr/local/bin/hostaffin-node-agent ]]; then
    # Try to download a prebuilt; if not, build locally (requires Go).
    local url="https://github.com/hostaffin/sgtm-platform/releases/latest/download/hostaffin-node-agent.linux-amd64"
    if curl -fsSL -o /usr/local/bin/hostaffin-node-agent "$url"; then
      ok "Downloaded prebuilt node-agent"
    else
      warn "Could not download prebuilt; attempting local build (Go ${GOLANG_VERSION} required)…"
      install_go_if_missing
      # Always (re)export PATH so the freshly-installed `go` is visible.
      export PATH="/usr/local/go/bin:/usr/local/bin:$PATH"
      hash -r 2>/dev/null || true
      if [[ ! -d "$PROJECT_DIR/node-agent/cmd/agent" ]]; then
        err "node-agent source not found at $PROJECT_DIR/node-agent/cmd/agent"
        err "Re-run after placing the source tree under $PROJECT_DIR,"
        err "or provide a working prebuilt URL."
        exit 1
      fi
      ( cd "$PROJECT_DIR/node-agent" \
          && go build -trimpath -ldflags="-s -w" \
                -o /usr/local/bin/hostaffin-node-agent ./cmd/agent )
    fi
    chmod 0755 /usr/local/bin/hostaffin-node-agent
  else
    ok "Node agent binary already present"
  fi
  cat >/etc/systemd/system/hostaffin-node-agent.service <<'EOF'
[Unit]
Description=Hostaffin sGTM Node Agent
After=docker.service
Requires=docker.service
[Service]
Type=simple
ExecStart=/usr/local/bin/hostaffin-node-agent
Restart=always
RestartSec=5
EnvironmentFile=/etc/hostaffin/hostaffin.env
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths=/var/run/docker.sock /letsencrypt
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now hostaffin-node-agent
  ok "Node agent installed and running"
}

install_go_if_missing() {
  if command -v go >/dev/null; then return 0; fi
  warn "Installing Go ${GOLANG_VERSION}…"
  local arch
  arch=$(uname -m)
  case "$arch" in
    x86_64)  arch="amd64" ;;
    aarch64) arch="arm64" ;;
    *)
      err "Unsupported arch for Go: $arch (only amd64/arm64 are downloadable)"
      return 1
      ;;
  esac
  local pkg="go${GOLANG_VERSION}.linux-${arch}.tar.gz"
  curl -fsSL -o /tmp/go.tgz "https://go.dev/dl/${pkg}"
  rm -rf /usr/local/go
  tar -C /usr/local -xzf /tmp/go.tgz
  ln -sf /usr/local/go/bin/go /usr/local/bin/go
  ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
  export PATH="/usr/local/go/bin:$PATH"
  hash -r 2>/dev/null || true
  go version
}

# ─────────────────────── Control plane + Admin panel ────────────────────
build_or_pull_images() {
  if [[ "$MODE" != "local" && "$MODE" != "controlplane" ]]; then return 0; fi
  hr; log "Preparing control-plane + admin-panel images…"
  # If we have a GHCR token, try to pull first (avoids building from source).
  if [[ -n "$GITHUB_TOKEN" ]]; then
    log "Logging in to ${GHCR_IMAGE_BASE}…"
    if echo "$GITHUB_TOKEN" \
       | docker login "$GHCR_IMAGE_BASE" -u x-access-token --password-stdin >/dev/null 2>&1; then
      log "Pulling control-plane image from ${GHCR_IMAGE_BASE}…"
      if ! docker pull "${GHCR_IMAGE_BASE}/control-plane:latest"; then
        warn "control-plane pull failed; will fall back to source build"
      else
        docker tag "${GHCR_IMAGE_BASE}/control-plane:latest" hostaffin/control-plane:latest
      fi
      log "Pulling admin-panel image from ${GHCR_IMAGE_BASE}…"
      if ! docker pull "${GHCR_IMAGE_BASE}/admin-panel:latest"; then
        warn "admin-panel pull failed; will fall back to source build"
      else
        docker tag "${GHCR_IMAGE_BASE}/admin-panel:latest" hostaffin/admin-panel:latest
      fi
    else
      warn "GHCR login failed; will build from local source instead"
    fi
  fi
  # Build from source if a corresponding directory exists and the image is
  # not already present (from a successful pull above).
  if [[ -d "$PROJECT_DIR/control-plane" ]] \
     && ! docker image inspect hostaffin/control-plane:latest >/dev/null 2>&1; then
    log "Building control-plane from source…"
    install_go_if_missing
    export PATH="/usr/local/go/bin:/usr/local/bin:$PATH"
    hash -r 2>/dev/null || true
    ( cd "$PROJECT_DIR/control-plane" \
        && docker build -t hostaffin/control-plane:latest . )
  fi
  if [[ -d "$PROJECT_DIR/admin-panel" ]] \
     && ! docker image inspect hostaffin/admin-panel:latest >/dev/null 2>&1; then
    log "Building admin-panel from source…"
    if ! command -v node >/dev/null; then
      warn "Installing Node.js ${NODE_VERSION}…"
      curl -fsSL "https://rpm.nodesource.com/setup_${NODE_VERSION}.x" | bash -
      pm_install nodejs
    fi
    ( cd "$PROJECT_DIR/admin-panel" \
        && docker build -t hostaffin/admin-panel:latest . )
  fi
  ok "Images prepared"
}

# ─────────────────────────── Docker compose stack ───────────────────────
write_compose_stack() {
  if [[ "$MODE" != "local" && "$MODE" != "controlplane" ]]; then return 0; fi
  hr; log "Writing docker-compose stack at $PROJECT_DIR…"
  cat >"$PROJECT_DIR/docker-compose.yml" <<'EOF'
services:
  postgres:
    image: postgres:16-alpine
    container_name: hostaffin-postgres
    environment:
      POSTGRES_USER: sgtm
      POSTGRES_PASSWORD: sgtm
      POSTGRES_DB: sgtm
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U sgtm -d sgtm"]
      interval: 5s
      timeout: 5s
      retries: 20

  redis:
    image: redis:7-alpine
    container_name: hostaffin-redis
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 20

  clickhouse:
    image: clickhouse/clickhouse-server:24-alpine
    container_name: hostaffin-clickhouse
    environment:
      CLICKHOUSE_DB: sgtm
      CLICKHOUSE_USER: sgtm
      CLICKHOUSE_PASSWORD: sgtm
    volumes:
      - chdata:/var/lib/clickhouse
    ulimits:
      nofile: { soft: 262144, hard: 262144 }

  control-plane:
    image: hostaffin/control-plane:latest
    container_name: hostaffin-control-plane
    depends_on:
      postgres:    { condition: service_healthy }
      redis:       { condition: service_healthy }
      clickhouse:  { condition: service_started }
    env_file: /etc/hostaffin/hostaffin.env
    ports:
      - "8080:8080"
    networks: [hostaffin_edge]

  worker:
    image: hostaffin/control-plane:latest
    container_name: hostaffin-worker
    depends_on:
      postgres:    { condition: service_healthy }
      redis:       { condition: service_healthy }
    command: ["/app/worker"]
    env_file: /etc/hostaffin/hostaffin.env
    networks: [hostaffin_edge]

  admin-panel:
    image: hostaffin/admin-panel:latest
    container_name: hostaffin-admin-panel
    depends_on:
      - control-plane
    environment:
      NEXT_PUBLIC_CONTROL_PLANE_URL: http://localhost:8080
      CONTROL_PLANE_URL: http://control-plane:8080
    ports:
      - "3000:3000"
    networks: [hostaffin_edge]

networks:
  hostaffin_edge:
    external: true

volumes:
  pgdata:
  chdata:
EOF
  ok "Compose stack written"
}

deploy_stack() {
  if [[ "$MODE" != "local" && "$MODE" != "controlplane" ]]; then return 0; fi
  hr; log "Deploying stack…"
  ( cd "$PROJECT_DIR" && docker compose up -d )
  ok "Stack deployed"
}

run_migrations() {
  if [[ "$MODE" != "local" && "$MODE" != "controlplane" ]]; then return 0; fi
  hr; log "Waiting for Postgres to be healthy…"
  local i=0
  until docker exec hostaffin-postgres pg_isready -U sgtm -d sgtm >/dev/null 2>&1; do
    i=$((i+1))
    if [[ $i -gt 60 ]]; then
      err "Postgres did not become healthy"
      err "Try: docker logs hostaffin-postgres"
      exit 1
    fi
    sleep 2
  done
  ok "Postgres ready"
  log "Running migrations + seed…"
  # Containers are named explicitly in write_compose_stack; look them up.
  local cpid
  cpid=$(docker ps -q -f name=^hostaffin-control-plane$ | head -n1)
  if [[ -z "$cpid" ]]; then
    err "control-plane container not running (expected: hostaffin-control-plane)"
    err "Try: cd $PROJECT_DIR && docker compose ps"
    exit 1
  fi
  docker exec "$cpid" /app/migrate up
  docker exec "$cpid" /app/seed
  ok "Migrations applied + seed loaded"
}

# ─────────────────────────── Health checks ──────────────────────────────
health_check() {
  hr; log "Running health checks…"
  sleep 3
  local api_ok=false
  local i
  for i in $(seq 1 20); do
    if curl -fsSL "http://localhost:8080/healthz" >/dev/null 2>&1; then
      api_ok=true; break
    fi
    sleep 2
  done
  if $api_ok; then ok "Control plane API healthy"; else warn "API not yet responding"; fi
  if command -v systemctl >/dev/null; then
    if systemctl is-active --quiet hostaffin-node-agent 2>/dev/null; then
      ok "node-agent running"
    else
      warn "node-agent NOT running (expected if MODE != local/master)"
    fi
    if systemctl is-active --quiet hostaffin-traefik 2>/dev/null; then
      ok "traefik running"
    else
      warn "traefik NOT running (expected if MODE != local/master)"
    fi
  fi
  docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || true
  ok "Health check complete"
}

# ─────────────────────────── Summary ────────────────────────────────────
print_summary() {
  local BOLD='\033[1m'
  local GREEN='\033[1;32m'
  local RESET='\033[0m'
  local ip
  ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  [[ -z "$ip" ]] && ip="<this-host>"

  cat <<EOF

${BOLD}${GREEN}
╔════════════════════════════════════════════════════════════════════╗
║           Hostaffin sGTM Platform — install complete              ║
╚════════════════════════════════════════════════════════════════════╝
${RESET}

Mode:                  $MODE
Project dir:           $PROJECT_DIR
Env file:              $ENV_FILE
Admin URL:             http://${ip}:3000
API URL:               http://${ip}:8080
Admin login:           admin@hostaffin.local
Admin password:        $(cat "$ADMIN_PWD_FILE" 2>/dev/null || echo "(see $ENV_FILE)")
Node ID:               $NODE_ID
Node API key:          $(grep '^NODE_API_KEY=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- || echo '(unset)')

Useful commands:
  systemctl status hostaffin-node-agent
  systemctl status hostaffin-traefik
  journalctl -u hostaffin-node-agent -f
  cd $PROJECT_DIR && docker compose logs -f

Log file: $LOG_FILE
EOF
}

# ──────────────────────────── Main flow ─────────────────────────────────
require_root
require_yum_distro

log "Hostaffin sGTM Platform installer"
log "Mode: $MODE"
log "OS:   $PRETTY_NAME $VERSION_ID"
[[ -n "$CONTROL_PLANE_URL" ]] && log "Control plane URL: $CONTROL_PLANE_URL"

if ! $NON_INTERACTIVE; then
  echo
  warn "This will install Docker, init/join a Swarm, and deploy services."
  confirm "Continue?" || { err "Aborted."; exit 5; }
fi

install_packages
tune_system
configure_firewalld
configure_selinux
install_docker
install_docker_completion
prepare_project
write_env
ensure_swarm
label_node_master
create_overlay_network
build_or_pull_images
write_compose_stack
deploy_stack
install_traefik_systemd
install_node_agent_systemd
run_migrations
health_check
print_summary

ok "Done."
