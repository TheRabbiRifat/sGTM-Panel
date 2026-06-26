#!/usr/bin/env bash
# ───────────────────────────────────────────────────────────────────────
# Hostaffin sGTM Hosting Platform — Uninstaller for YUM-family distros
# ───────────────────────────────────────────────────────────────────────
# Reverses everything installed by install-yum.sh:
#
#   ✓ Stops + disables hostaffin-{node-agent,traefik} systemd units
#   ✓ Tears down the docker-compose stack (postgres, redis, clickhouse,
#     control-plane, worker, admin-panel)
#   ✓ Removes Traefik container and /letsencrypt ACME data
#   ✓ Removes hostaffin_* docker networks and labelled nodes
#   ✓ Leaves the host in a Swarm (drain + leave instead of force-rm)
#   ✓ Optionally removes the /opt/hostaffin workspace
#   ✓ Optionally removes the /etc/hostaffin env file
#   ✓ Optionally removes sysctl / limits / firewalld rules
#   ✓ Optionally removes the hostaffin SELinux module
#
# Modes (must match the install mode used):
#   --mode local          Undo a local-mode install       (default)
#   --mode master         Undo a master-mode install
#   --mode controlplane   Undo a controlplane-mode install
#
# Flags:
#   --purge            Also remove /opt/hostaffin, /etc/hostaffin,
#                      /var/log/hostaffin, /var/log/traefik, /letsencrypt,
#                      /root/.hostaffin-admin-password and the admin password
#                      from /etc/hostaffin/hostaffin.env
#   --leave-swarm      Just drain the node; do NOT execute `docker swarm leave`
#   --keep-firewall    Do not roll back firewalld rules
#   --keep-sysctl      Do not remove /etc/sysctl.d/99-hostaffin.conf
#   --keep-ulimits     Do not remove /etc/security/limits.d/99-hostaffin.conf
#   --keep-docker      Do NOT uninstall Docker Engine
#   --non-interactive  Skip confirmation prompts
#   --yes              Alias for --non-interactive
#
# Usage:
#   sudo ./uninstall-yum.sh [--mode MODE] [--purge] [--non-interactive]
#                            [--keep-firewall] [--keep-sysctl]
#                            [--keep-ulimits] [--keep-docker]
#                            [--leave-swarm]
#
# Environment overrides:
#   HOSTAFFIN_MODE, HOSTAFFIN_PURGE, HOSTAFFIN_LEAVE_SWARM
#   HOSTAFFIN_KEEP_FIREWALL, HOSTAFFIN_KEEP_SYSCTL, HOSTAFFIN_KEEP_ULIMITS
#   HOSTAFFIN_KEEP_DOCKER, HOSTAFFIN_NON_INTERACTIVE
#
# Exit codes:
#   0  success (or partial success — see log)
#   1  generic failure
#   2  invalid arguments
#   3  not running as root
#   5  user aborted
# ───────────────────────────────────────────────────────────────────────

set -euo pipefail
IFS=$'\n\t'

# Handle --help before sourcing lib-pm.sh, so docs read on a non-RPM host
# still work.
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

# Use the same package-manager detection as the installer so removal works
# on either dnf (RHEL 8+, Fedora, Alma, Rocky, CentOS Stream, OL 8+, AL2023)
# or yum (RHEL 7, CentOS 7, Amazon Linux 2).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib-pm.sh"
pm_detect || true

# Color codes used by print_summary (declared here so they're always in scope).
BOLD='\033[1m'; GREEN='\033[1;32m'; RESET='\033[0m'

# ───────────────────────────── Defaults ─────────────────────────────────
MODE="${HOSTAFFIN_MODE:-local}"
PURGE="${HOSTAFFIN_PURGE:-false}"
LEAVE_SWARM="${HOSTAFFIN_LEAVE_SWARM:-false}"
KEEP_FIREWALL="${HOSTAFFIN_KEEP_FIREWALL:-false}"
KEEP_SYSCTL="${HOSTAFFIN_KEEP_SYSCTL:-false}"
KEEP_ULIMITS="${HOSTAFFIN_KEEP_ULIMITS:-false}"
KEEP_DOCKER="${HOSTAFFIN_KEEP_DOCKER:-false}"
NON_INTERACTIVE="${HOSTAFFIN_NON_INTERACTIVE:-false}"

PROJECT_DIR="/opt/hostaffin"
LOG_DIR="/var/log/hostaffin"
ENV_FILE="/etc/hostaffin/hostaffin.env"
ADMIN_PWD_FILE="/root/.hostaffin-admin-password"
DOCKER_VOLUMES=(pgdata chdata)

# ──────────────────────────── Logging helpers ───────────────────────────
log()  { printf '\033[1;34m[uninst]\033[0m %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m[  ok  ]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[ warn ]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[ err  ]\033[0m %s\n' "$*" >&2; }
hr()   { printf '\n\033[1;36m%s\033[0m\n' "──────────────────────────────────────────────────────────────" >&2; }

# ─────────────────────────── Argument parsing ───────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)             MODE="$2"; shift 2 ;;
    --purge)            PURGE=true; shift ;;
    --leave-swarm)      LEAVE_SWARM=true; shift ;;
    --keep-firewall)    KEEP_FIREWALL=true; shift ;;
    --keep-sysctl)      KEEP_SYSCTL=true; shift ;;
    --keep-ulimits)     KEEP_ULIMITS=true; shift ;;
    --keep-docker)      KEEP_DOCKER=true; shift ;;
    --non-interactive|--yes) NON_INTERACTIVE=true; shift ;;
    -h|--help)          exit 0 ;;  # handled before script body
    *) err "Unknown argument: $1"; exit 2 ;;
  esac
done

# Validate mode up-front so we can fail fast on typos.
case "$MODE" in
  local|master|controlplane) ;;
  *) err "Invalid --mode '$MODE'. Must be one of: local, master, controlplane."; exit 2 ;;
esac

# ─────────────────────── Initialise logging sink ───────────────────────
# Done after arg parsing so --help prints to the terminal cleanly.
mkdir -p "$LOG_DIR" 2>/dev/null || true
LOG_FILE="$LOG_DIR/uninstall-$(date -u +%Y%m%d%H%M%S).log"
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

confirm() {
  if $NON_INTERACTIVE; then return 0; fi
  local prompt="$1"
  local default="${2:-n}"
  local ans
  read -rp "$(printf '\033[1;33m[?]\033[0m %s [%s]: ' "$prompt" "$default")" ans
  ans="${ans:-$default}"
  case "${ans,,}" in
    y|yes) return 0 ;;
    *)     return 1 ;;
  esac
}

# ─────────────────────────── Best-effort helpers ────────────────────────
# run_soft: run a command but never abort the uninstall on failure
run_soft() {
  if "$@"; then
    return 0
  fi
  warn "Command failed (continuing): $*"
  return 0
}

# ───────────────────────────── systemd units ────────────────────────────
stop_systemd_units() {
  hr; log "Stopping hostaffin systemd units…"
  local units=(
    hostaffin-node-agent.service
    hostaffin-traefik.service
  )
  for u in "${units[@]}"; do
    if systemctl list-unit-files "$u" >/dev/null 2>&1; then
      run_soft systemctl stop "$u"
      run_soft systemctl disable "$u"
    else
      log "  · $u not installed, skipping"
    fi
  done
  ok "Systemd units stopped"
}

remove_systemd_units() {
  hr; log "Removing systemd unit files…"
  local files=(
    /etc/systemd/system/hostaffin-node-agent.service
    /etc/systemd/system/hostaffin-traefik.service
    /etc/systemd/system/traefik.service.d/override.conf
  )
  for f in "${files[@]}"; do
    if [[ -e "$f" ]]; then
      run_soft rm -rf "$f"
    fi
  done
  run_soft systemctl daemon-reload
  run_soft systemctl reset-failed hostaffin-node-agent.service || true
  run_soft systemctl reset-failed hostaffin-traefik.service   || true
  ok "Systemd unit files removed"
}

# ─────────────────────────── Docker artefacts ───────────────────────────
remove_traefik_container() {
  hr; log "Removing Traefik container…"
  if command -v docker >/dev/null; then
    if docker ps -a --format '{{.Names}}' | grep -qx 'hostaffin-traefik'; then
      run_soft docker rm -f hostaffin-traefik
    else
      log "  · hostaffin-traefik container not present"
    fi
  fi
  ok "Traefik container removed"
}

tear_down_compose_stack() {
  if [[ "$MODE" != "local" && "$MODE" != "controlplane" ]]; then
    return 0
  fi
  hr; log "Tearing down docker-compose stack…"
  if [[ -f "$PROJECT_DIR/docker-compose.yml" ]]; then
    ( cd "$PROJECT_DIR" && run_soft docker compose down --remove-orphans ) || true
  else
    log "  · $PROJECT_DIR/docker-compose.yml not present; stopping containers by name"
    local names=(
      hostaffin-control-plane
      hostaffin-worker
      hostaffin-admin-panel
      sgtm-postgres
      sgtm-redis
      sgtm-clickhouse
    )
    for n in "${names[@]}"; do
      if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$n"; then
        run_soft docker rm -f "$n"
      fi
    done
  fi
  ok "Compose stack torn down"
}

remove_docker_volumes() {
  if ! $PURGE; then
    log "  · Skipping volume removal (use --purge to remove)"
    return 0
  fi
  hr; log "Removing Docker volumes (pgdata, chdata)…"
  for v in "${DOCKER_VOLUMES[@]}"; do
    if docker volume ls --format '{{.Name}}' 2>/dev/null | grep -qx "$v"; then
      run_soft docker volume rm "$v"
    fi
  done
  # Also handle compose-prefixed volume names (projectname_pgdata)
  local project_vols
  project_vols=$(docker volume ls --format '{{.Name}}' 2>/dev/null | grep -E '(pgdata|chdata)$' || true)
  for v in $project_vols; do
    run_soft docker volume rm "$v"
  done
  ok "Docker volumes removed"
}

remove_hostaffin_images() {
  if ! $PURGE; then
    return 0
  fi
  hr; log "Removing Hostaffin-built Docker images…"
  local imgs
  imgs=$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null \
    | grep -E '^(hostaffin/(control-plane|admin-panel))' || true)
  if [[ -n "$imgs" ]]; then
    while IFS= read -r img; do
      [[ -n "$img" ]] && run_soft docker rmi "$img"
    done <<< "$imgs"
  fi
  ok "Images removed"
}

remove_node_label() {
  if ! command -v docker >/dev/null; then
    return 0
  fi
  if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
    return 0
  fi
  hr; log "Removing hostaffin_role=master label…"
  local self
  self=$(docker node ls --format '{{.Self}} {{.ID}}' 2>/dev/null \
         | awk '$1=="true"{print $2; exit}')
  if [[ -n "$self" ]]; then
    run_soft docker node update --label-rm hostaffin_role=master "$self"
  fi
  ok "Node label removed"
}

remove_overlay_networks() {
  if ! command -v docker >/dev/null; then
    return 0
  fi
  hr; log "Removing hostaffin_edge overlay network…"
  if docker network ls --format '{{.Name}}' 2>/dev/null | grep -qx 'hostaffin_edge'; then
    run_soft docker network rm hostaffin_edge
  else
    log "  · hostaffin_edge not present"
  fi
  ok "Overlay network removed"
}

handle_swarm_membership() {
  if ! command -v docker >/dev/null; then
    return 0
  fi
  if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
    log "  · Node is not in a Swarm; nothing to do"
    return 0
  fi
  hr; log "Handling Swarm membership…"
  local self
  self=$(docker node ls --format '{{.Self}} {{.ID}}' 2>/dev/null \
         | awk '$1=="true"{print $2; exit}')
  if [[ -n "$self" ]]; then
    log "  · Draining self…"
    run_soft docker node update --availability drain "$self"
  fi
  if $LEAVE_SWARM; then
    log "  · --leave-swarm set; NOT executing 'docker swarm leave'"
    return 0
  fi
  if confirm "Drain and 'docker swarm leave' this node? (other nodes will retain quorum)" n; then
    run_soft docker swarm leave
  else
    log "  · Skipping 'docker swarm leave' per user"
  fi
  ok "Swarm membership handled"
}

# ─────────────────────────── Project artefacts ──────────────────────────
remove_workspace() {
  if ! $PURGE; then
    log "  · Keeping $PROJECT_DIR (use --purge to remove)"
    return 0
  fi
  hr; log "Removing project workspace $PROJECT_DIR…"
  if [[ -d "$PROJECT_DIR" ]]; then
    run_soft rm -rf "$PROJECT_DIR"
  fi
  ok "Workspace removed"
}

remove_etc_hostaffin() {
  if ! $PURGE; then
    log "  · Keeping $ENV_FILE (use --purge to remove)"
    return 0
  fi
  hr; log "Removing /etc/hostaffin…"
  if [[ -d /etc/hostaffin ]]; then
    run_soft rm -rf /etc/hostaffin
  fi
  [[ -f "$ADMIN_PWD_FILE" ]] && run_soft rm -f "$ADMIN_PWD_FILE"
  ok "/etc/hostaffin removed"
}

remove_logs() {
  if ! $PURGE; then
    log "  · Keeping $LOG_DIR (use --purge to remove)"
    return 0
  fi
  hr; log "Removing Hostaffin log directories…"
  [[ -d "$LOG_DIR" ]] && run_soft rm -rf "$LOG_DIR"
  [[ -d /var/log/traefik ]] && run_soft rm -rf /var/log/traefik
  [[ -d /letsencrypt ]] && run_soft rm -rf /letsencrypt
  ok "Logs removed"
}

remove_binary() {
  if ! $PURGE; then
    return 0
  fi
  if [[ -x /usr/local/bin/hostaffin-node-agent ]]; then
    hr; log "Removing hostaffin-node-agent binary…"
    run_soft rm -f /usr/local/bin/hostaffin-node-agent
    ok "Binary removed"
  fi
}

# ─────────────────────────── System tuning ──────────────────────────────
remove_sysctl() {
  if $KEEP_SYSCTL; then
    log "  · Keeping /etc/sysctl.d/99-hostaffin.conf (per --keep-sysctl)"
    return 0
  fi
  hr; log "Removing Hostaffin sysctl overrides…"
  if [[ -f /etc/sysctl.d/99-hostaffin.conf ]]; then
    run_soft rm -f /etc/sysctl.d/99-hostaffin.conf
    run_soft sysctl --system
  fi
  ok "Sysctl overrides removed"
}

remove_ulimits() {
  if $KEEP_ULIMITS; then
    log "  · Keeping /etc/security/limits.d/99-hostaffin.conf (per --keep-ulimits)"
    return 0
  fi
  hr; log "Removing Hostaffin ulimits overrides…"
  if [[ -f /etc/security/limits.d/99-hostaffin.conf ]]; then
    run_soft rm -f /etc/security/limits.d/99-hostaffin.conf
  fi
  ok "Ulimits overrides removed"
}

# ─────────────────────────── Firewalld ─────────────────────────────────
remove_firewalld_rules() {
  if $KEEP_FIREWALL; then
    log "  · Keeping firewalld rules (per --keep-firewall)"
    return 0
  fi
  if ! command -v firewall-cmd >/dev/null; then
    return 0
  fi
  hr; log "Removing Hostaffin firewalld rules…"
  local ports=(
    "2377/tcp" "7946/tcp" "7946/udp" "4789/udp"
    "8080/tcp" "3000/tcp" "9100/tcp" "8123/tcp" "9000/tcp"
  )
  for p in "${ports[@]}"; do
    run_soft firewall-cmd --permanent --remove-port="$p"
  done
  # http/https were added as services; only remove if we added them.
  # We can't tell whether the operator added them, so just leave them.
  run_soft firewall-cmd --reload
  ok "Firewalld rules removed"
}

# ─────────────────────────── SELinux ───────────────────────────────────
remove_selinux_module() {
  if ! command -v semodule >/dev/null; then
    return 0
  fi
  hr; log "Removing Hostaffin SELinux module…"
  if semodule -l 2>/dev/null | grep -qx 'hostaffin'; then
    run_soft semodule -r hostaffin
  fi
  ok "SELinux module processed"
}

# ─────────────────────────── Docker (optional) ─────────────────────────
remove_docker() {
  if $KEEP_DOCKER; then
    log "  · Keeping Docker Engine (per --keep-docker)"
    return 0
  fi
  if ! command -v docker >/dev/null; then
    return 0
  fi
  hr; log "Uninstalling Docker Engine…"
  if ! confirm "Remove Docker Engine + Compose plugin? (other workloads on this host will be affected)" n; then
    log "  · Skipped per user"
    return 0
  fi
  run_soft pm_remove docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras || true
  ok "Docker Engine packages removed"
}

# ─────────────────────────── Summary ────────────────────────────────────
print_summary() {
  cat <<EOF

${BOLD}${GREEN}
╔════════════════════════════════════════════════════════════════════╗
║         Hostaffin sGTM Platform — uninstall complete              ║
╚════════════════════════════════════════════════════════════════════╝
${RESET}

Mode:                  $MODE
Purge:                 $PURGE
Leave Swarm:           $LEAVE_SWARM
Kept Docker:           $KEEP_DOCKER
Kept Firewall:         $KEEP_FIREWALL
Kept sysctl:           $KEEP_SYSCTL
Kept ulimits:          $KEEP_ULIMITS
Project dir:           $( [[ -d $PROJECT_DIR ]] && echo "$PROJECT_DIR (still present)" || echo "$PROJECT_DIR (removed)" )
Env file:              $( [[ -f $ENV_FILE ]] && echo "$ENV_FILE (still present)" || echo "$ENV_FILE (removed)" )
Log file:              $LOG_FILE

If you also want to re-enable swap that the installer disabled, run:
  # restore the backup created at /etc/fstab.bak (if present)
  # or manually re-add the swap entry.

EOF
}

# ──────────────────────────── Main flow ─────────────────────────────────
require_root

log "Hostaffin sGTM Platform uninstaller"
log "Mode: $MODE"
if $PURGE; then
  warn "PURGE mode — /opt/hostaffin, /etc/hostaffin, /letsencrypt and the"
  warn "        admin password file will be DELETED."
fi

if ! $NON_INTERACTIVE; then
  echo
  warn "This will stop and remove Hostaffin services, containers, and (with"
  warn "--purge) configuration. It is NOT destructive to other workloads"
  warn "unless you also confirm the Docker removal step."
  confirm "Continue with uninstall?" || { err "Aborted."; exit 5; }
fi

stop_systemd_units
remove_traefik_container
tear_down_compose_stack
remove_docker_volumes
remove_hostaffin_images
remove_node_label
remove_overlay_networks
handle_swarm_membership
remove_systemd_units
remove_workspace
remove_etc_hostaffin
remove_logs
remove_binary
remove_sysctl
remove_ulimits
remove_firewalld_rules
remove_selinux_module
remove_docker

print_summary
ok "Done."
