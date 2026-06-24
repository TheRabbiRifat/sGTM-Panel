#!/usr/bin/env bash
# ───────────────────────────────────────────────────────────────────────
# install-interactive.sh — Hostaffin sGTM Platform interactive wizard
# ───────────────────────────────────────────────────────────────────────
# A guided, ASCII-UI installer that walks you through every important
# decision, then hands off to the canonical install-almalinux9.sh script
# (the underlying installer, which now supports any YUM-family distro and
# auto-detects dnf vs yum via lib-pm.sh).
#
# It prompts for:
#   • Timezone
#   • Public DNS wildcard hostname (e.g. edge.hostaffin.com)
#   • Install mode (local / master / controlplane)
#   • Master-node join token + manager addr (when joining)
#   • Admin email + password
#   • Optional GitHub token (for pulling prebuilt images)
#
# It shows:
#   • ASCII art banner
#   • Step-by-step progress bar
#   • Spinners for each install step
#   • Final ASCII summary
#
# Usage:
#   sudo ./install-interactive.sh
#
# Non-interactive flags:
#   --non-interactive  Reuse env / skip prompts (still uses ASCII UI)
#   --config FILE      Load answers from a previously-saved config file
#   --save-config FILE Save answers to FILE after prompting
# ───────────────────────────────────────────────────────────────────────

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib-ui.sh"

# ──────────────────────────── Defaults ──────────────────────────────────
HOSTAFFIN_VERSION="${HOSTAFFIN_VERSION:-1.0.0}"
CONFIG_FILE=""
SAVE_CONFIG=""
NON_INTERACTIVE_CLI=false
TZ="${TZ:-}"
DNS_WILDCARD="${HOSTAFFIN_DNS_WILDCARD:-}"
MODE="${HOSTAFFIN_MODE:-}"
JOIN_TOKEN="${HOSTAFFIN_JOIN_TOKEN:-}"
MANAGER_ADDR="${HOSTAFFIN_MANAGER_ADDR:-}"
CONTROL_PLANE_URL="${HOSTAFFIN_CONTROL_PLANE_URL:-}"
ADMIN_EMAIL="${HOSTAFFIN_ADMIN_EMAIL:-}"
ADMIN_PASSWORD="${HOSTAFFIN_ADMIN_PASSWORD:-}"
NODE_ID="${HOSTAFFIN_NODE_ID:-}"
NODE_API_KEY="${HOSTAFFIN_NODE_API_KEY:-}"
GITHUB_TOKEN="${HOSTAFFIN_GITHUB_TOKEN:-}"
SKIP_FIREWALL=false
SKIP_SWAP=false

# ──────────────────────────── CLI flags ─────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)          CONFIG_FILE="$2"; shift 2 ;;
    --save-config)     SAVE_CONFIG="$2"; shift 2 ;;
    --non-interactive) NON_INTERACTIVE_CLI=true; shift ;;
    -h|--help)
      sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) ui_err "Unknown argument: $1"; exit 2 ;;
  esac
done

# ──────────────────────────── Pre-flight ────────────────────────────────
require_root() {
  if [[ $EUID -ne 0 ]]; then
    ui_err "This script must be run as root. Try: sudo $0"
    exit 3
  fi
}

require_yum_distro() {
  if [[ ! -f /etc/os-release ]]; then
    ui_err "Cannot detect /etc/os-release"
    exit 4
  fi
  # shellcheck disable=SC1091
  . /etc/os-release

  # Accept any YUM-family distro: Alma / Rocky / RHEL / CentOS Stream /
  # Oracle / Fedora / Amazon Linux. Anything apt/deb-based is rejected
  # here because the rest of the stack assumes RPM and dnf/yum.
  local id="${ID:-}"
  local id_like="${ID_LIKE:-}"
  local ok=0
  case "$id" in
    almalinux|rocky|rhel|centos|fedora|ol|amzn) ok=1 ;;
  esac
  if [[ "$id_like" == *"rhel"* || "$id_like" == *"centos"* || "$id_like" == *"fedora"* ]]; then
    ok=1
  fi

  if [[ $ok -eq 0 ]]; then
    ui_err "This installer requires a YUM-family distro (dnf or yum)."
    ui_err "Detected: ${id:-unknown} ${VERSION_ID:-} (id_like='${id_like:-}')."
    ui_err "Re-run on AlmaLinux / Rocky / RHEL / CentOS Stream / Oracle / Fedora / Amazon Linux,"
    ui_err "or fork the script for your distro."
    exit 4
  fi

  # Auto-detect dnf vs yum via lib-pm.sh.
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib-pm.sh"
  pm_detect || { ui_err "Neither dnf nor yum was found in PATH."; exit 4; }
  export HOSTAFFIN_PM="$PM_GLOBAL"
  ui_info "Detected YUM-family distro: ${PRETTY_NAME:-?} (using $PM_GLOBAL)"
}

# ──────────────────────────── Config save/load ──────────────────────────
save_config() {
  local f="$1"
  umask 077
  cat >"$f" <<EOF
# Hostaffin sGTM Platform — installer answers
# Generated $(date -u +%Y-%m-%dT%H:%M:%SZ)
TZ=$TZ
DNS_WILDCARD=$DNS_WILDCARD
MODE=$MODE
JOIN_TOKEN=$JOIN_TOKEN
MANAGER_ADDR=$MANAGER_ADDR
CONTROL_PLANE_URL=$CONTROL_PLANE_URL
ADMIN_EMAIL=$ADMIN_EMAIL
ADMIN_PASSWORD=$ADMIN_PASSWORD
NODE_ID=$NODE_ID
NODE_API_KEY=$NODE_API_KEY
GITHUB_TOKEN=$GITHUB_TOKEN
SKIP_FIREWALL=$SKIP_FIREWALL
SKIP_SWAP=$SKIP_SWAP
EOF
  chmod 0600 "$f"
  ui_ok "Saved answers to $f"
}

load_config() {
  local f="$1"
  [[ -f "$f" ]] || { ui_err "Config file not found: $f"; exit 2; }
  # shellcheck disable=SC1090
  source "$f"
  ui_ok "Loaded answers from $f"
}

# ──────────────────────────── Wizard steps ──────────────────────────────
wizard_welcome() {
  ui_clear
  ui_banner
  cat <<EOF
${C_BOLD}Welcome!${C_RESET}
This wizard will install the Hostaffin sGTM Platform on this host.
You'll be asked a few questions; sensible defaults are provided.

${C_DIM}You can press ${C_RESET}${C_BOLD}Enter${C_RESET}${C_DIM} to accept a default,
or ${C_RESET}${C_BOLD}Ctrl+C${C_RESET}${C_DIM} to abort at any time.${C_RESET}

${C_DIM}A copy of your answers can be saved to a file at the end of
this wizard, so you can re-run unattended with --config FILE.${C_RESET}
EOF
  ui_hr
}

ui_clear() {
  if [[ -t 1 ]] && command -v clear >/dev/null; then
    clear
  fi
}

ask_timezone() {
  ui_step_banner 1 "Timezone"
  echo "${C_DIM}Used for log timestamps, scheduled jobs, and ACME renewal windows.${C_RESET}" >&2
  echo >&2
  local detected=""
  if [[ -f /etc/localtime ]]; then
    detected=$(readlink /etc/localtime 2>/dev/null | sed 's|/usr/share/zoneinfo/||')
  fi
  [[ -z "$detected" ]] && detected="UTC"
  local default="${TZ:-$detected}"
  while :; do
    TZ=$(ui_prompt "Timezone (Region/City, e.g. Europe/Berlin)" "$default")
    if ui_validate_timezone "$TZ"; then break; fi
    ui_warn "Timezone '$TZ' not found in /usr/share/zoneinfo."
    ui_info "Examples: UTC, Europe/Berlin, America/New_York, Asia/Dhaka"
  done
  if [[ -f "/usr/share/zoneinfo/$TZ" ]]; then
    ln -sf "/usr/share/zoneinfo/$TZ" /etc/localtime
  fi
  ui_ok "Timezone set to $TZ"
  ui_step_done
}

ask_dns_wildcard() {
  ui_step_banner 2 "Public DNS wildcard hostname"
  cat <<EOF >&2
${C_DIM}Customers' tracking hostnames will be subdomains of this base
domain. You'll need to create a wildcard DNS A/AAAA record that
points to one or more master nodes once installation finishes.

Example: ${C_RESET}${C_BOLD}edge.hostaffin.com${C_RESET}${C_DIM} → wildcard *.edge.hostaffin.com${C_RESET}
EOF
  echo >&2
  local default="${DNS_WILDCARD:-edge.$(hostname -d 2>/dev/null || echo hostaffin.com)}"
  while :; do
    DNS_WILDCARD=$(ui_prompt "DNS wildcard base domain" "$default")
    if ui_validate_hostname "$DNS_WILDCARD"; then break; fi
    ui_warn "Not a valid DNS hostname."
  done
  ui_ok "DNS wildcard base: $DNS_WILDCARD"
  ui_info "After install, create: *.$DNS_WILDCARD  →  <this node IP>"
  ui_step_done
}

ask_mode() {
  ui_step_banner 3 "Install mode"
  cat <<EOF >&2
${C_DIM}Every node in the cluster is a MASTER node — there is no
separate "edge" or "slave" role. All nodes can serve traffic.${C_RESET}
EOF
  echo >&2
  local opts=(
    "local          — single-host all-in-one (DB + control plane + Traefik + node agent)"
    "master         — join an existing Swarm as another master node"
    "controlplane   — control plane + DB stack only (no Traefik / node agent)"
  )
  local pick
  pick=$(ui_choose "Select install mode:" "${opts[@]}")
  case "$pick" in
    1) MODE="local" ;;
    2) MODE="master" ;;
    3) MODE="controlplane" ;;
  esac
  ui_ok "Mode: $MODE"
  ui_step_done
}

ask_master_join() {
  ui_step_banner 4 "Swarm join details"
  cat <<EOF >&2
${C_DIM}You're joining an existing Swarm. Get these values from the
manager node's installer output, or run on the manager:
  ${C_RESET}${C_BOLD}docker swarm join-token worker${C_RESET}${C_DIM}${C_RESET}
EOF
  echo >&2
  while :; do
    MANAGER_ADDR=$(ui_prompt "Manager address (e.g. 10.0.0.10:2377)" \
      "${MANAGER_ADDR:-127.0.0.1:2377}")
    if [[ "$MANAGER_ADDR" =~ ^[A-Za-z0-9._-]+:[0-9]+$ ]]; then break; fi
    ui_warn "Format must be host:port"
  done
  echo >&2
  while :; do
    JOIN_TOKEN=$(ui_prompt "Worker join token" "$JOIN_TOKEN")
    [[ -n "$JOIN_TOKEN" ]] && break
    ui_warn "Join token is required for master mode"
  done
  ui_ok "Will join swarm at $MANAGER_ADDR"
  ui_step_done
}

ask_control_plane_url() {
  ui_step_banner 4 "Control plane URL"
  cat <<EOF >&2
${C_DIM}This is the URL node agents and admin panel use to reach the
control plane's API. If installing locally, use the hostname/IP
other nodes can reach.${C_RESET}
EOF
  echo >&2
  local default="${CONTROL_PLANE_URL:-https://cp.${DNS_WILDCARD}}"
  while :; do
    CONTROL_PLANE_URL=$(ui_prompt "Control plane URL" "$default")
    if ui_validate_url "$CONTROL_PLANE_URL"; then break; fi
    ui_warn "Must be a valid http(s) URL"
  done
  ui_ok "Control plane URL: $CONTROL_PLANE_URL"
  ui_step_done
}

ask_admin() {
  ui_step_banner 5 "Admin account"
  cat <<EOF >&2
${C_DIM}The super-admin account for the admin panel.${C_RESET}
EOF
  echo >&2
  local default="${ADMIN_EMAIL:-admin@${DNS_WILDCARD}}"
  ADMIN_EMAIL=$(ui_prompt "Admin email" "$default")
  while :; do
    ui_info "Leave blank to auto-generate a strong password"
    ADMIN_PASSWORD=$(ui_password "Admin password (input hidden)")
    if [[ -z "$ADMIN_PASSWORD" ]]; then
      ADMIN_PASSWORD=$(openssl rand -base64 18 | tr -d '=+/')
      ui_ok "Generated admin password"
      break
    fi
    if [[ ${#ADMIN_PASSWORD} -ge 10 ]]; then
      local confirm_pw
      confirm_pw=$(ui_password "Confirm admin password")
      if [[ "$confirm_pw" == "$ADMIN_PASSWORD" ]]; then
        break
      fi
      ui_warn "Passwords do not match — try again"
    else
      ui_warn "Password must be at least 10 characters"
    fi
  done
  ui_step_done
}

ask_optional() {
  ui_step_banner 6 "Optional: image registry"
  cat <<EOF >&2
${C_DIM}If you have a GitHub Container Registry token, the installer
can pull prebuilt control-plane and admin-panel images instead of
building from source. Leave blank to build from local source.${C_RESET}
EOF
  echo >&2
  GITHUB_TOKEN=$(ui_prompt "GHCR token (blank to skip)" "${GITHUB_TOKEN:-}")
  ui_step_done
}

ask_advanced() {
  ui_step_banner 7 "Advanced options"
  echo "${C_DIM}Tune these only if you know what you're doing.${C_RESET}" >&2
  echo >&2
  if ui_confirm "Skip firewall configuration?" "n"; then
    SKIP_FIREWALL=true
  fi
  if ui_confirm "Keep swap enabled (not recommended)?" "n"; then
    SKIP_SWAP=true
  fi
  if [[ "$MODE" == "local" ]]; then
    local default_id="master-$(hostname -s | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')-01"
    NODE_ID=$(ui_prompt "Node ID" "${NODE_ID:-$default_id}")
  fi
  ui_step_done
}

review_and_confirm() {
  ui_step_banner 8 "Review"
  cat <<EOF >&2
${C_BOLD}${C_BCYAN}Please review your answers:${C_RESET}
${C_DIM}──────────────────────────────────────────────────────────────────────${C_RESET}
  Timezone:        $TZ
  DNS wildcard:    $DNS_WILDCARD
  Mode:            $MODE
EOF
  if [[ "$MODE" == "master" ]]; then
    cat <<EOF >&2
  Manager addr:    $MANAGER_ADDR
  Join token:      ${JOIN_TOKEN:0:8}… (truncated)
EOF
  fi
  if [[ "$MODE" == "local" || "$MODE" == "controlplane" ]]; then
    cat <<EOF >&2
  Control plane:   $CONTROL_PLANE_URL
EOF
  fi
  cat <<EOF >&2
  Admin email:     $ADMIN_EMAIL
  Admin password:  $([[ -n "$ADMIN_PASSWORD" ]] && echo "(set, ${#ADMIN_PASSWORD} chars)" || echo "(auto-generate)")
  GHCR token:      $([[ -n "$GITHUB_TOKEN" ]] && echo "(set)" || echo "(none)")
  Skip firewall:   $SKIP_FIREWALL
  Keep swap:       $SKIP_SWAP
${C_DIM}──────────────────────────────────────────────────────────────────────${C_RESET}
EOF
  echo >&2
  ui_confirm "Proceed with installation?" "y" || { ui_err "Aborted."; exit 5; }
  ui_step_done
}

# ──────────────────────────── Run installer ─────────────────────────────
run_installer() {
  ui_hr
  ui_info "Handing off to the YUM-family installer with collected options…"
  ui_hr

  local args=(
    "--mode" "$MODE"
  )
  if [[ "$MODE" == "master" ]]; then
    args+=( "--join-token" "$JOIN_TOKEN" "--manager-addr" "$MANAGER_ADDR" )
  fi
  if [[ -n "$CONTROL_PLANE_URL" ]]; then
    args+=( "--control-plane-url" "$CONTROL_PLANE_URL" )
  fi
  if [[ -n "$NODE_ID" ]]; then
    args+=( "--node-id" "$NODE_ID" )
  fi
  if [[ -n "$NODE_API_KEY" ]]; then
    args+=( "--node-api-key" "$NODE_API_KEY" )
  fi
  if [[ -n "$GITHUB_TOKEN" ]]; then
    args+=( "--github-token" "$GITHUB_TOKEN" )
  fi
  if [[ -n "$ADMIN_PASSWORD" ]]; then
    export HOSTAFFIN_ADMIN_PASSWORD="$ADMIN_PASSWORD"
  fi
  if $SKIP_FIREWALL; then args+=( "--skip-firewall" ); fi
  if $SKIP_SWAP;     then args+=( "--skip-swap-disable" ); fi
  args+=( "--non-interactive" )

  HOSTAFFIN_DNS_WILDCARD="$DNS_WILDCARD" \
    "$SCRIPT_DIR/install-almalinux9.sh" "${args[@]}"
}

# ──────────────────────────── Final summary ─────────────────────────────
final_summary() {
  local ip
  ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  [[ -z "$ip" ]] && ip="<this-host>"

  cat <<EOF >&2

${C_BOLD}${C_BGREEN}
   ╔══════════════════════════════════════════════════════════════════╗
   ║                  🎉  Installation complete!                       ║
   ╚══════════════════════════════════════════════════════════════════╝
${C_RESET}
${C_BOLD}Your Hostaffin sGTM Platform is ready.${C_RESET}

${C_BOLD}${C_BCYAN}Service URLs${C_RESET}
${C_DIM}──────────────────────────────────────────────────────────────────────${C_RESET}
  Admin panel:        ${C_UNDER}http://${ip}:3000${C_RESET}
  Control plane API:  ${C_UNDER}http://${ip}:8080${C_RESET}
  Health check:       ${C_UNDER}http://${ip}:8080/healthz${C_RESET}

${C_BOLD}${C_BCYAN}Login${C_RESET}
${C_DIM}──────────────────────────────────────────────────────────────────────${C_RESET}
  Email:              $ADMIN_EMAIL
  Password:           $ADMIN_PASSWORD

${C_BOLD}${C_BCYAN}DNS (do this before going live)${C_RESET}
${C_DIM}──────────────────────────────────────────────────────────────────────${C_RESET}
  Create a wildcard record for your DNS base:
    ${C_BOLD}*.${DNS_WILDCARD}${C_RESET}  →  ${C_BOLD}${ip}${C_RESET}

${C_BOLD}${C_BCYAN}Useful commands${C_RESET}
${C_DIM}──────────────────────────────────────────────────────────────────────${C_RESET}
  systemctl status hostaffin-node-agent
  systemctl status hostaffin-traefik
  cd /opt/hostaffin && docker compose ps
  docker compose logs -f

${C_BOLD}${C_BYELLOW}Reminder${C_RESET}
  Save the admin password somewhere safe. The installer will not
  show it again.

EOF
  if [[ -n "$SAVE_CONFIG" ]]; then
    save_config "$SAVE_CONFIG"
  fi
}

# ──────────────────────────── Main ──────────────────────────────────────
require_root
require_yum_distro

# Load config if provided
if [[ -n "$CONFIG_FILE" ]]; then
  load_config "$CONFIG_FILE"
fi

# Decide: interactive or use the loaded/CLI-provided values
if [[ -n "$CONFIG_FILE" ]] || $NON_INTERACTIVE_CLI; then
  # Validate we have minimum required values
  : "${TZ:?TZ required}"
  : "${DNS_WILDCARD:?DNS_WILDCARD required}"
  : "${MODE:?MODE required}"
  if [[ "$MODE" == "master" ]]; then
    : "${JOIN_TOKEN:?JOIN_TOKEN required for master mode}"
    : "${MANAGER_ADDR:?MANAGER_ADDR required for master mode}"
  fi
else
  wizard_welcome
  ui_init_steps 8
  ask_timezone
  ask_dns_wildcard
  ask_mode
  if [[ "$MODE" == "master" ]]; then
    ask_master_join
  elif [[ "$MODE" == "local" || "$MODE" == "controlplane" ]]; then
    ask_control_plane_url
  fi
  ask_admin
  ask_optional
  ask_advanced
  review_and_confirm
fi

# Save config if requested (even in --non-interactive)
if [[ -n "$SAVE_CONFIG" && -z "$CONFIG_FILE" ]]; then
  save_config "$SAVE_CONFIG"
fi

# Hand off to the real installer
run_installer

# Show the friendly summary
final_summary
