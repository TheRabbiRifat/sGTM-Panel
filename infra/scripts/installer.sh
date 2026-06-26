#!/usr/bin/env bash
# ───────────────────────────────────────────────────────────────────────
# Hostaffin sGTM Platform — unified installer
# ───────────────────────────────────────────────────────────────────────
# One script, four subcommands, fully self-contained. cPanel-style.
#
# USAGE
#   sudo ./installer.sh <subcommand> [flags]
#
# SUBCOMMANDS
#   install         Provision a host (default if no subcommand given).
#   uninstall       Reverse an install.
#   interactive     ASCII wizard that prompts for everything.
#   health-check    Verify Docker, Swarm, services, ports.
#   -h | --help     Print this help and exit.
#
# INSTALL MODES (used by `install` and `uninstall`)
#   --mode local          All-in-one single host (default)
#   --mode master         Join an existing Swarm as a master node
#   --mode controlplane   Control plane + DB stack only (no Traefik / node-agent)
#
# INSTALL FLAGS
#   --join-token TOKEN          Swarm join token (required for --mode master)
#   --manager-addr ADDR         <ip>:2377 of an existing manager (master)
#   --control-plane-url URL     Public URL of the control plane
#   --node-id ID                Override auto-generated master-<host>-01
#   --node-api-key KEY          Pre-shared HMAC key with the control plane
#   --github-token TOKEN        GHCR PAT for pulling prebuilt images
#   --project-dir DIR           Override /opt/hostaffin
#   --non-interactive           Skip confirmation prompts
#   --skip-firewall             Don't touch firewalld
#   --skip-swap-disable         Keep swap enabled
#
# UNINSTALL FLAGS
#   --purge                     Also remove /opt/hostaffin, /etc/hostaffin,
#                               /var/log/hostaffin, /letsencrypt, admin pwd file
#   --leave-swarm               Don't run `docker swarm leave`
#   --keep-firewall             Keep firewalld rules
#   --keep-sysctl               Keep /etc/sysctl.d/99-hostaffin.conf
#   --keep-ulimits              Keep /etc/security/limits.d/99-hostaffin.conf
#   --keep-docker               Don't uninstall Docker Engine
#
# ADVANCED / SELF-BOOTSTRAP
#   --from-url URL              Download this script from URL (with SHA verify)
#   --sha256 HASH               Expected SHA-256 of the downloaded script
#   --env-file PATH             Load HOSTAFFIN_* vars from PATH (mode 0400/0600)
#
# ENVIRONMENT VARIABLES (alternative to flags)
#   HOSTAFFIN_MODE, HOSTAFFIN_JOIN_TOKEN, HOSTAFFIN_MANAGER_ADDR,
#   HOSTAFFIN_CONTROL_PLANE_URL, HOSTAFFIN_NODE_ID, HOSTAFFIN_NODE_API_KEY,
#   HOSTAFFIN_GITHUB_TOKEN, HOSTAFFIN_ADMIN_PASSWORD, HOSTAFFIN_ADMIN_EMAIL,
#   HOSTAFFIN_PM=dnf|yum, HOSTAFFIN_GHCR_IMAGE_BASE, HOSTAFFIN_INSTALL_URL
#
# SUPPORTED DISTROS (YUM-family only)
#   AlmaLinux 8/9 · Rocky 8/9 · RHEL 8/9 · CentOS Stream 8/9
#   Oracle Linux 8/9 · Fedora 36+ · Amazon Linux 2 / 2023
#
# EXIT CODES
#   0 success · 1 generic failure · 2 invalid args · 3 not root
#   4 unsupported OS · 5 user aborted
# ───────────────────────────────────────────────────────────────────────

set -euo pipefail
IFS=$'\n\t'

# ═════════════════════════════════════════════════════════════════════════
# SECTION 1 — CONSTANTS
# ═════════════════════════════════════════════════════════════════════════
VERSION="1.0.0"
DOCKER_VERSION="26.1.3"
GOLANG_VERSION="1.22.5"
NODE_VERSION="20"
PROJECT_DIR="/opt/hostaffin"
LOG_DIR="/var/log/hostaffin"
ENV_FILE="/etc/hostaffin/hostaffin.env"
ADMIN_PWD_FILE="/root/.hostaffin-admin-password"
GHCR_IMAGE_BASE="${HOSTAFFIN_GHCR_IMAGE_BASE:-ghcr.io/hostaffin}"
GHCR_NODE_AGENT_RELEASE="https://github.com/hostaffin/sgtm-platform/releases/latest/download/hostaffin-node-agent.linux-amd64"
DOCKER_VOLUMES=(pgdata chdata)
FIREWALL_PORTS=(2377/tcp 7946/tcp 7946/udp 4789/udp 8080/tcp 3000/tcp 9100/tcp 8123/tcp 9000/tcp)
FIREWALL_SVCS=(ssh http https)

# ═════════════════════════════════════════════════════════════════════════
# SECTION 2 — LOGGING + UI HELPERS
# ═════════════════════════════════════════════════════════════════════════
_log()  { printf '\033[1;34m[install]\033[0m %s\n' "$*" >&2; }
_ok()   { printf '\033[1;32m[  ok  ]\033[0m %s\n' "$*" >&2; }
_warn() { printf '\033[1;33m[ warn ]\033[0m %s\n' "$*" >&2; }
_err()  { printf '\033[1;31m[ err  ]\033[0m %s\n' "$*" >&2; }
_hr()   { printf '\n\033[1;36m%s\033[0m\n' "──────────────────────────────────────────────────────────────" >&2; }

# run_soft: execute but never abort the caller on failure
run_soft() {
  if "$@"; then return 0; fi
  _warn "Command failed (continuing): $*"
  return 0
}

# Color setup for the interactive wizard
# shellcheck disable=SC2034  # these are consumed dynamically inside printf argument lists
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'; C_UNDER=$'\033[4m'
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'; C_CYAN=$'\033[36m'
  C_BRED=$'\033[91m'; C_BGREEN=$'\033[92m'; C_BYELLOW=$'\033[93m'
  C_BCYAN=$'\033[96m'; C_BMAGENTA=$'\033[95m'
else
  C_RESET=; C_BOLD=; C_DIM=; C_UNDER=
  C_RED=; C_GREEN=; C_YELLOW=; C_BLUE=; C_CYAN=
  C_BRED=; C_BGREEN=; C_BYELLOW=; C_BCYAN=; C_BMAGENTA=
fi
export C_RESET C_BOLD C_DIM C_UNDER C_RED C_GREEN C_YELLOW C_BLUE C_CYAN
export C_BRED C_BGREEN C_BYELLOW C_BCYAN C_BMAGENTA

# ─────────── Wizard UI helpers (used by `interactive` subcommand) ───────
ui_banner() {
  printf '%s' "$C_BOLD$C_BCYAN" >&2
  cat <<'BANNER' >&2
   _   _           _     __        _    __ _ _           _
  | | | | ___  ___| |__ / _| ___  | |  / _(_) | ___  ___| |__
  | |_| |/ _ \/ __| '_ \ |_ / _ \ | | | |_| | |/ _ \/ __| '_ \
  |  _  |  __/\__ \ | | |  | (_) || | |  _| | |  __/\__ \ | | |
  |_| |_|\___||___/_| |_|_|  \___/ |_| |_| |_|_|\___||___/_| |_|
BANNER
  printf '%s' "$C_RESET" >&2
  printf '%s                  sGTM Hosting Platform · v%s%s\n' "$C_DIM" "$VERSION" "$C_RESET" >&2
  printf '\n' >&2
}

ui_step_banner() {
  local n="$1"; local title="$2"
  printf '\n%s╔══ Step %s ══╗%s\n' "$C_BOLD$C_BMAGENTA" "$n" "$C_RESET" >&2
  printf '%s║%s  %s  %s║%s\n' "$C_BOLD$C_BMAGENTA" "$C_RESET" "$title" "$C_BOLD$C_BMAGENTA" "$C_RESET" >&2
  printf '%s╚═══════════════╝%s\n' "$C_BOLD$C_BMAGENTA" "$C_RESET" >&2
}

ui_prompt() {
  local q="$1" default="${2:-}" ans
  if [[ -n "$default" ]]; then
    read -rp "$(printf '%s[?]%s %s %s[%s]%s: ' \
      "$C_BOLD$C_BYELLOW" "$C_RESET" "$q" \
      "$C_DIM" "$default" "$C_RESET")" ans
    ans="${ans:-$default}"
  else
    read -rp "$(printf '%s[?]%s %s%s: ' \
      "$C_BOLD$C_BYELLOW" "$C_RESET" "$q" "$C_RESET")" ans
  fi
  printf '%s' "$ans"
}

ui_password() {
  local q="$1" ans
  read -rsp "$(printf '%s[?]%s %s%s: ' \
    "$C_BOLD$C_BYELLOW" "$C_RESET" "$q" "$C_RESET")" ans
  printf '\n' >&2
  printf '%s' "$ans"
}

ui_confirm() {
  local q="$1" default="${2:-y}" ans
  read -rp "$(printf '%s[?]%s %s %s[y/N]%s: ' \
    "$C_BOLD$C_BYELLOW" "$C_RESET" "$q" \
    "$C_DIM" "$C_RESET")" ans
  ans="${ans:-$default}"
  [[ "${ans,,}" == y || "${ans,,}" == yes ]]
}

ui_choose() {
  local q="$1"; shift
  local opts=("$@")
  printf '%s[?]%s %s\n' "$C_BOLD$C_BYELLOW" "$C_RESET" "$q" >&2
  local i=1
  for o in "${opts[@]}"; do
    printf '    %s%d)%s %s\n' "$C_DIM" "$i" "$C_RESET" "$o" >&2
    i=$((i+1))
  done
  local ans
  while :; do
    read -rp "$(printf '%s   > %s' "$C_BOLD" "$C_RESET")" ans
    [[ -z "$ans" ]] && ans=1
    if [[ "$ans" =~ ^[0-9]+$ ]] && (( ans >= 1 && ans <= ${#opts[@]} )); then
      printf '%d' "$ans"
      return 0
    fi
    printf '%s[ warn ]%s Please enter 1-%d\n' "$C_BOLD$C_BYELLOW" "$C_RESET" "${#opts[@]}" >&2
  done
}

ui_validate_hostname() {
  local h="$1"
  [[ -z "$h" ]] && return 1
  [[ ${#h} -le 253 ]] || return 1
  [[ "$h" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$ ]]
}

ui_validate_url() {
  [[ "$1" =~ ^https?://[A-Za-z0-9._-]+(:[0-9]+)?(/.*)?$ ]]
}

ui_clear() { [[ -t 1 ]] && command -v clear >/dev/null && clear || true; }

# Wizard progress (init_steps N → step_done prints N/M after each step)
__UI_TOTAL_STEPS=0; __UI_CURRENT_STEP=0
ui_init_steps() { __UI_TOTAL_STEPS="$1"; __UI_CURRENT_STEP=0; }
ui_step_done()  {
  __UI_CURRENT_STEP=$(( __UI_CURRENT_STEP + 1 ))
  printf '%s[%d/%d]%s complete\n' "$C_DIM" "$__UI_CURRENT_STEP" "$__UI_TOTAL_STEPS" "$C_RESET" >&2
}

# ═════════════════════════════════════════════════════════════════════════
# SECTION 3 — PACKAGE MANAGER (inlined lib-pm.sh)
# ═════════════════════════════════════════════════════════════════════════
PM_GLOBAL="${PM_GLOBAL:-${HOSTAFFIN_PM:-}}"

pm_detect() {
  if [[ -n "$PM_GLOBAL" ]]; then
    command -v "$PM_GLOBAL" >/dev/null 2>&1 || {
      _err "HOSTAFFIN_PM=$PM_GLOBAL was requested but not found in PATH"; return 1;
    }
    return 0
  fi
  if command -v dnf >/dev/null 2>&1; then PM_GLOBAL="dnf"
  elif command -v yum >/dev/null 2>&1; then PM_GLOBAL="yum"
  else _err "Neither dnf nor yum found in PATH"; return 1; fi
  export PM_GLOBAL
}

pm_install() { pm_detect; case "$PM_GLOBAL" in dnf) dnf -y install "$@" ;; yum) yum -y install "$@" ;; *) _err "unsupported PM '$PM_GLOBAL'"; return 1 ;; esac; }
pm_remove()  { pm_detect; case "$PM_GLOBAL" in dnf) dnf -y remove  "$@" ;; yum) yum -y remove  "$@" ;; *) _err "unsupported PM '$PM_GLOBAL'"; return 1 ;; esac; }
pm_addrepo() {
  local url="$1"; pm_detect
  case "$PM_GLOBAL" in
    dnf) pm_install dnf-plugins-core >/dev/null 2>&1 || true; dnf config-manager --add-repo "$url" ;;
    yum) pm_install yum-utils >/dev/null 2>&1 || true
         if command -v yum-config-manager >/dev/null 2>&1; then
           yum-config-manager --add-repo "$url"
         else
           local fname; fname="/etc/yum.repos.d/$(basename "${url%%\?*}")"
           curl -fsSL "$url" -o "$fname"
         fi ;;
    *) _err "unsupported PM '$PM_GLOBAL'"; return 1 ;;
  esac
}

# ═════════════════════════════════════════════════════════════════════════
# SECTION 4 — PREFLIGHT
# ═════════════════════════════════════════════════════════════════════════
require_root() { [[ $EUID -eq 0 ]] || { _err "Must be run as root. Try: sudo $0"; exit 3; }; }

require_yum_distro() {
  [[ -f /etc/os-release ]] || { _err "Cannot detect /etc/os-release"; exit 4; }
  # shellcheck disable=SC1091
  . /etc/os-release
  local id="${ID:-}" like="${ID_LIKE:-}"
  if ! { [[ "$id" =~ ^(almalinux|rocky|rhel|centos|fedora|ol|amzn)$ ]] \
        || [[ "$like" == *rhel* || "$like" == *centos* || "$like" == *fedora* ]]; }; then
    _err "Requires a YUM-family distro (dnf or yum)."
    _err "Detected: ${id:-?} ${VERSION_ID:-}. Run on Alma / Rocky / RHEL / CentOS Stream / Oracle / Fedora / Amazon Linux."
    exit 4
  fi
  pm_detect || { _err "Neither dnf nor yum found in PATH"; exit 4; }
  _log "Detected: $PRETTY_NAME (using $PM_GLOBAL)"
}

confirm() {
  $NON_INTERACTIVE && return 0
  local ans default="${1:-y}"
  if [[ $# -ge 2 ]]; then local prompt="$1"; default="$2"; else local prompt="Continue?"; fi
  read -rp "$(printf '\033[1;33m[?]\033[0m %s [%s]: ' "$prompt" "$default")" ans
  ans="${ans:-$default}"
  [[ "${ans,,}" == y || "${ans,,}" == yes ]]
}

# ═════════════════════════════════════════════════════════════════════════
# SECTION 5 — SELF-BOOTSTRAP (--from-url / --env-file)
# ═════════════════════════════════════════════════════════════════════════
# If invoked with --from-url, download this very script to a private
# working dir, verify its SHA-256, re-exec, then scrub the dir.
# If invoked with --env-file, load HOSTAFFIN_* vars from a 0400/0600 file
# BEFORE parsing any other flags.
SUBCOMMAND=""
FROM_URL=""
EXPECTED_SHA=""
ENV_FILE_FLAG=""
ASSUME_YES=false

# Pre-parse: env-file must be loaded first so subsequent flags see the vars.
pre_parse_env_file() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --env-file) ENV_FILE_FLAG="$2"; shift 2 ;;
      --from-url|--sha256|-h|--help|install|uninstall|interactive|health-check)
        return ;;  # handled by main parser
      *) shift ;;
    esac
  done
}

load_env_file() {
  [[ -z "$ENV_FILE_FLAG" ]] && return 0
  [[ -f "$ENV_FILE_FLAG" ]] || { _err "Env file not found: $ENV_FILE_FLAG"; exit 1; }
  local mode
  mode="$(stat -c '%a' "$ENV_FILE_FLAG" 2>/dev/null || stat -f '%Lp' "$ENV_FILE_FLAG" 2>/dev/null || echo "?")"
  case "$mode" in
    600|400) ;;
    *) _err "Env file $ENV_FILE_FLAG has insecure mode ($mode). Run: sudo chmod 0600 '$ENV_FILE_FLAG'"; exit 1 ;;
  esac
  local key val
  while IFS='=' read -r key val; do
    [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
    val="${val%\"}"; val="${val#\"}"; val="${val%\'}"; val="${val#\'}"
    [[ "$key" =~ ^HOSTAFFIN_[A-Z0-9_]+$ ]] || { _err "Refusing non-HOSTAFFIN_ var: $key"; exit 1; }
    export "$key"="$val"
  done < <(grep -E '^[[:space:]]*HOSTAFFIN_[A-Z0-9_]+=' "$ENV_FILE_FLAG" || true)
  _ok "Loaded env from $ENV_FILE_FLAG"
}

# ─────────── Self-bootstrap from URL ───────────
# When run as `curl -fsSL URL | sudo bash -s -- --from-url URL --sha256 HASH install …`,
# we download to a private dir, verify, and re-exec from disk so BASH_SOURCE
# works normally for the rest of the script.
WORK_DIR=""
# shellcheck disable=SC2329  # invoked via trap
cleanup_bootstrap() {
  local code=$?
  if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
    command -v shred >/dev/null 2>&1 && find "$WORK_DIR" -type f -exec shred -u {} + 2>/dev/null || true
    rm -rf -- "$WORK_DIR" 2>/dev/null || true
  fi
  exit "$code"
}

self_bootstrap() {
  [[ -n "$FROM_URL" ]] || return 0
  WORK_DIR="$(mktemp -d -t hostaffin-installer-XXXXXX)"
  chmod 0700 "$WORK_DIR"
  trap cleanup_bootstrap EXIT INT TERM
  local target="$WORK_DIR/installer.sh"
  _log "Self-bootstrap: downloading $FROM_URL"
  if ! curl -fsSL --proto '=https' --tlsv1.2 -o "$target" "$FROM_URL"; then
    _err "Download failed: $FROM_URL"; exit 1
  fi
  chmod 0600 "$target"
  if [[ -n "$EXPECTED_SHA" ]]; then
    local got
    got="$(sha256sum "$target" | awk '{print $1}')"
    if [[ "$got" != "$EXPECTED_SHA" ]]; then
      _err "SHA-256 mismatch. expected=$EXPECTED_SHA got=$got"; exit 1
    fi
    _ok "SHA-256 verified"
  fi
  _log "Re-executing from $target"
  # Re-exec preserving the env-file flag (so the re-exec'd process loads it
  # too) and stripping --from-url / --sha256 + their values from the rest of
  # the original argv. We rebuild a clean argv instead of shifting a snapshot
  # of "$@" — the previous version used `for a in "$@"; shift` which doesn't
  # actually mutate the live positional params.
  local -a new_argv=( "$target" )
  [[ -n "$ENV_FILE_FLAG" ]] && new_argv+=( --env-file "$ENV_FILE_FLAG" )
  local skip_next=0 a
  for a in "$@"; do
    if [[ $skip_next -eq 1 ]]; then skip_next=0; continue; fi
    case "$a" in
      --from-url|--sha256) skip_next=1 ;;   # consume flag + its value
      *)                   new_argv+=( "$a" ) ;;
    esac
  done
  exec "${new_argv[@]}"
}

# ═════════════════════════════════════════════════════════════════════════
# SECTION 6 — ARGUMENT PARSING
# ═════════════════════════════════════════════════════════════════════════
# Defaults
MODE="${HOSTAFFIN_MODE:-local}"
JOIN_TOKEN="${HOSTAFFIN_JOIN_TOKEN:-}"
MANAGER_ADDR="${HOSTAFFIN_MANAGER_ADDR:-}"
CONTROL_PLANE_URL="${HOSTAFFIN_CONTROL_PLANE_URL:-}"
NODE_ID="${HOSTAFFIN_NODE_ID:-}"
NODE_API_KEY="${HOSTAFFIN_NODE_API_KEY:-}"
GITHUB_TOKEN="${HOSTAFFIN_GITHUB_TOKEN:-}"
ADMIN_EMAIL="${HOSTAFFIN_ADMIN_EMAIL:-}"
ADMIN_PASSWORD="${HOSTAFFIN_ADMIN_PASSWORD:-}"
DNS_WILDCARD="${HOSTAFFIN_DNS_WILDCARD:-}"
TZ_NAME="${TZ:-}"
PURGE=false
LEAVE_SWARM=false
KEEP_FIREWALL=false
KEEP_SYSCTL=false
KEEP_ULIMITS=false
KEEP_DOCKER=false
NON_INTERACTIVE=false
SKIP_FIREWALL=false
SKIP_SWAP=false
SAVE_CONFIG=""

print_help() {
  awk '/^# ─/{ i++; next } i==2 { sub(/^# ?/, ""); print } i>=3 { exit }' "$0"
}

# Main parser. The first non-flag-prefixed argument is the subcommand.
# If none is given (first arg starts with `-`), default to `install`.
parse_args() {
  # Pre-pass: pull out top-level bootstrap flags (--env-file, --from-url,
  # --sha256, -y/--yes, -h/--help) so the rest of the parser sees only
  # subcommand + per-subcommand flags.
  local rest=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --env-file)         ENV_FILE_FLAG="$2"; shift 2 ;;
      --from-url)         FROM_URL="$2";     shift 2 ;;
      --sha256)           EXPECTED_SHA="$2"; shift 2 ;;
      -y|--yes|--assume-yes) ASSUME_YES=true; shift ;;
      -h|--help)          print_help; exit 0 ;;
      *)                  rest+=( "$1" ); shift ;;
    esac
  done
  set -- "${rest[@]}"

  # If we have at least one arg and it's not a flag, it MUST be the subcommand.
  if [[ $# -gt 0 && "$1" != -* ]]; then
    case "$1" in
      install|uninstall|interactive|health-check|help)
        SUBCOMMAND="$1"; shift ;;
      *)
        _err "Unknown subcommand: $1"; print_help; exit 2 ;;
    esac
  else
    SUBCOMMAND="install"
  fi
  $ASSUME_YES && NON_INTERACTIVE=true

  # Subcommand-specific flags
  while [[ $# -gt 0 ]]; do
    case "$1" in
      # install + uninstall
      --mode)              MODE="$2"; shift 2 ;;
      --non-interactive|--yes) NON_INTERACTIVE=true; shift ;;

      # install only
      --join-token)        JOIN_TOKEN="$2"; shift 2 ;;
      --manager-addr)      MANAGER_ADDR="$2"; shift 2 ;;
      --control-plane-url) CONTROL_PLANE_URL="$2"; shift 2 ;;
      --node-id)           NODE_ID="$2"; shift 2 ;;
      --node-api-key)      NODE_API_KEY="$2"; shift 2 ;;
      --github-token)      GITHUB_TOKEN="$2"; shift 2 ;;
      --project-dir)       PROJECT_DIR="$2"; shift 2 ;;
      --skip-firewall)     SKIP_FIREWALL=true; shift ;;
      --skip-swap-disable) SKIP_SWAP=true; shift ;;
      --save-config)       SAVE_CONFIG="$2"; shift 2 ;;

      # uninstall only
      --purge)             PURGE=true; shift ;;
      --leave-swarm)       LEAVE_SWARM=true; shift ;;
      --keep-firewall)     KEEP_FIREWALL=true; shift ;;
      --keep-sysctl)       KEEP_SYSCTL=true; shift ;;
      --keep-ulimits)      KEEP_ULIMITS=true; shift ;;
      --keep-docker)       KEEP_DOCKER=true; shift ;;

      -h|--help) print_help; exit 0 ;;
      *) _err "Unknown argument: $1"; exit 2 ;;
    esac
  done
}

validate_common() {
  case "$MODE" in
    local|master|controlplane) ;;
    *) _err "Invalid --mode '$MODE'. Must be: local, master, controlplane."; exit 2 ;;
  esac
  if [[ "$MODE" == "master" && ( -z "$JOIN_TOKEN" || -z "$MANAGER_ADDR" ) ]]; then
    _err "--mode master requires both --join-token and --manager-addr."
    exit 2
  fi
}

mode_runs_db()   { [[ "$MODE" == "local" || "$MODE" == "controlplane" ]]; }
mode_runs_edge() { [[ "$MODE" == "local" || "$MODE" == "master" ]]; }

# ═════════════════════════════════════════════════════════════════════════
# SECTION 7 — INSTALL STEPS
# ═════════════════════════════════════════════════════════════════════════
install_go_if_missing() {
  command -v go >/dev/null && return 0
  _warn "Installing Go ${GOLANG_VERSION}"
  local arch; arch=$(uname -m)
  case "$arch" in
    x86_64)  arch="amd64" ;;
    aarch64) arch="arm64" ;;
    *) _err "Unsupported arch for Go: $arch"; return 1 ;;
  esac
  local pkg="go${GOLANG_VERSION}.linux-${arch}.tar.gz"
  curl -fsSL -o /tmp/go.tgz "https://go.dev/dl/${pkg}"
  rm -rf /usr/local/go
  tar -C /usr/local -xzf /tmp/go.tgz
  ln -sf /usr/local/go/bin/go    /usr/local/bin/go
  ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
  export PATH="/usr/local/go/bin:$PATH"
  hash -r 2>/dev/null || true
  go version
}

install_node_if_missing() {
  command -v node >/dev/null && return 0
  _warn "Installing Node.js ${NODE_VERSION}"
  curl -fsSL "https://rpm.nodesource.com/setup_${NODE_VERSION}.x" | bash -
  pm_install nodejs
}

step_packages() {
  _hr; _log "Installing base packages"
  pm_install curl wget tar gzip ca-certificates yum-utils epel-release \
              git make jq openssl firewalld policycoreutils-python-utils \
              rsync htop bind-utils \
    || { _err "$PM_GLOBAL install failed"; exit 1; }
  _ok "Base packages installed"
}

step_system_tuning() {
  _hr; _log "Tuning system"
  if ! $SKIP_SWAP && swapon --show | grep -q .; then
    swapoff -a
    sed -i.bak '/\bswap\b/d' /etc/fstab
  fi
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
  cat >/etc/security/limits.d/99-hostaffin.conf <<'EOF'
*    soft nofile 65535
*    hard nofile 65535
*    soft nproc  65535
*    hard nproc  65535
root soft nofile 65535
root hard nofile 65535
root soft nproc  65535
root hard nproc  65535
EOF
  _ok "System tuned"
}

step_firewalld() {
  $SKIP_FIREWALL && { _warn "Skipping firewall (--skip-firewall)"; return; }
  _hr; _log "Configuring firewalld"
  systemctl enable --now firewalld
  for s in "${FIREWALL_SVCS[@]}"; do
    firewall-cmd --permanent --add-service="$s" >/dev/null
  done
  for p in "${FIREWALL_PORTS[@]}"; do
    firewall-cmd --permanent --add-port="$p" >/dev/null
  done
  firewall-cmd --reload
  _ok "Firewall rules applied"
}

step_selinux() {
  if ! command -v getenforce >/dev/null; then _log "SELinux not installed; skipping"; return; fi
  [[ "$(getenforce)" == "Enforcing" ]] || { _warn "SELinux not enforcing; skipping"; return; }
  _hr; _log "Adjusting SELinux"
  setsebool -P container_manage_cgroup 1 || true
  setsebool -P domain_can_mmap_files  1 || true
  if ! semodule -l 2>/dev/null | grep -qx 'hostaffin'; then
    cat >/tmp/hostaffin.te <<'EOF'
module hostaffin 1.0;
require {
  type unconfined_service_t; type etc_t; type var_log_t; type container_file_t;
  class file { create open read write getattr setattr unlink append rename };
  class dir  { add_name create open read write getattr setattr remove_name rmdir search };
}
allow unconfined_service_t etc_t:file           { create open read write getattr setattr unlink append rename };
allow unconfined_service_t var_log_t:dir        { add_name create open read write getattr setattr remove_name rmdir search };
allow unconfined_service_t container_file_t:dir { add_name create open read write getattr setattr remove_name rmdir search };
EOF
    checkmodule -M -m -o /tmp/hostaffin.mod /tmp/hostaffin.te 2>/dev/null || true
    semodule_package -o /tmp/hostaffin.pp /tmp/hostaffin.mod 2>/dev/null || true
    semodule -i /tmp/hostaffin.pp 2>/dev/null || true
  fi
  _ok "SELinux adjusted"
}

step_docker() {
  _hr; _log "Installing Docker Engine ${DOCKER_VERSION}"
  if command -v docker >/dev/null; then
    local cur; cur="$(docker --version | awk '{print $3}' | tr -d ',')"
    if [[ "$cur" == "$DOCKER_VERSION" ]]; then
      _ok "Docker ${DOCKER_VERSION} already installed"
    else
      _warn "Existing Docker ${cur}; leaving in place"
    fi
  else
    pm_remove docker docker-client docker-client-latest docker-common \
               docker-latest docker-latest-logrotate docker-engine podman runc 2>/dev/null || true
    pm_addrepo https://download.docker.com/linux/centos/docker-ce.repo
    pm_install "docker-ce-${DOCKER_VERSION}" "docker-ce-cli-${DOCKER_VERSION}" \
               containerd.io docker-buildx-plugin docker-compose-plugin
  fi
  systemctl enable --now docker
  systemctl is-active --quiet docker || { _err "Docker failed to start"; exit 1; }
  curl -fsSL https://raw.githubusercontent.com/docker/compose/v2.27.1/contrib/completion/bash/docker-compose \
       -o /etc/bash_completion.d/docker-compose 2>/dev/null || true
  _ok "Docker is running"
}

step_project_layout() {
  _hr; _log "Preparing project workspace at $PROJECT_DIR"
  mkdir -p "$PROJECT_DIR/traefik" "$PROJECT_DIR/control-plane/keys" /etc/hostaffin
  chmod 750 /etc/hostaffin
  _ok "Workspace prepared"
}

step_env_file() {
  _hr; _log "Writing environment file $ENV_FILE"
  local keydir="$PROJECT_DIR/control-plane/keys"
  if [[ ! -f "$keydir/private.pem" ]]; then
    openssl genpkey -algorithm RSA -out "$keydir/private.pem" -pkeyopt rsa_keygen_bits:2048 2>/dev/null
    openssl rsa -in "$keydir/private.pem" -pubout -out "$keydir/public.pem" 2>/dev/null
  fi
  local admin_pwd="${ADMIN_PASSWORD:-$(openssl rand -base64 18 | tr -d '=+/')}"
  local node_secret="${NODE_API_KEY:-$(openssl rand -hex 24)}"
  [[ -z "$NODE_ID" ]] && NODE_ID="master-$(hostname -s | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')-01"
  local admin_email="${ADMIN_EMAIL:-admin@${DNS_WILDCARD:-hostaffin.local}}"

  cat >"$ENV_FILE" <<EOF
# Hostaffin sGTM Platform — generated $(date -u +%Y-%m-%dT%H:%M:%SZ)
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

EDGE_DOMAIN=${DNS_WILDCARD:-edge.hostaffin.local}

ADMIN_BOOTSTRAP_EMAIL=$admin_email
ADMIN_BOOTSTRAP_PASSWORD=$admin_pwd

GITHUB_TOKEN=$GITHUB_TOKEN
EOF

  # Inline PEM blocks (single shell-quoted lines with literal \n).
  {
    printf 'JWT_PRIVATE_KEY_PEM="'
    printf '%s\\n' '-----BEGIN RSA PRIVATE KEY-----'
    tr -d '\n' < "$keydir/private.pem" | fold -w 64 | sed 's/.*/&\\n/'
    printf '%s\\n' '-----END RSA PRIVATE KEY-----'
    printf '"\n'
    printf 'JWT_PUBLIC_KEY_PEM="'
    printf '%s\\n' '-----BEGIN PUBLIC KEY-----'
    tr -d '\n' < "$keydir/public.pem" | fold -w 64 | sed 's/.*/&\\n/'
    printf '%s\\n' '-----END PUBLIC KEY-----'
    printf '"\n'
  } > "$ENV_FILE.pems"

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$ENV_FILE" "$ENV_FILE.pems" <<'PY'
import sys, pathlib
env, pems = sys.argv[1], sys.argv[2]
pem = pathlib.Path(pems).read_text()
text = pathlib.Path(env).read_text().replace("__JWT_PRIVATE_KEY_PEM__", "").replace("__JWT_PUBLIC_KEY_PEM__", "")
needle = "JWT_ACCESS_TTL=15m\n"
pathlib.Path(env).write_text(text.replace(needle, pem + needle, 1))
PY
  else
    awk -v pems="$ENV_FILE.pems" '
      /__JWT_PRIVATE_KEY_PEM__/ { while ((getline line < pems) > 0) print line; next }
      /__JWT_PUBLIC_KEY_PEM__/  { while ((getline line < pems) > 0) print line; next }
      { print }
    ' "$ENV_FILE" > "$ENV_FILE.tmp" && mv "$ENV_FILE.tmp" "$ENV_FILE"
  fi
  rm -f "$ENV_FILE.pems"
  grep -q '__JWT_' "$ENV_FILE" 2>/dev/null && { _err "Failed to inline JWT keys"; exit 1; }
  chmod 0640 "$ENV_FILE"

  printf '%s' "$admin_pwd" > "$ADMIN_PWD_FILE"
  chmod 0600 "$ADMIN_PWD_FILE"
  _ok "Environment written to $ENV_FILE"
  [[ -t 2 ]] && printf '\n\033[1;33m[warn]\033[0m Admin password: \033[1m%s\033[0m  (save it now!)\n' "$admin_pwd" >&2
  ADMIN_PASSWORD="$admin_pwd"
}

step_swarm() {
  _hr; _log "Configuring Docker Swarm"
  if docker info 2>/dev/null | grep -q "Swarm: active"; then _ok "Already in a Swarm"; return; fi
  case "$MODE" in
    local|controlplane)
      local advertise; advertise=$(hostname -I 2>/dev/null | awk '{print $1}')
      [[ -z "$advertise" ]] && advertise="127.0.0.1"
      if ! docker swarm init --advertise-addr "$advertise" 2>/dev/null; then
        _warn "swarm init with $advertise failed; retrying on 127.0.0.1"
        docker swarm init --advertise-addr 127.0.0.1
      fi
      _ok "Swarm initialised as manager (advertise $advertise)" ;;
    master)
      docker swarm join --token "$JOIN_TOKEN" "$MANAGER_ADDR" 2377
      _ok "Joined swarm" ;;
  esac
}

step_node_label() {
  mode_runs_edge || return
  _log "Labelling node as master"
  local self="" i=0
  while (( i < 30 )); do
    self=$(docker node ls --format '{{.Self}} {{.ID}}' 2>/dev/null \
           | awk '$1=="true"{print $2; exit}')
    [[ -n "$self" ]] && break
    sleep 1; ((i++))
  done
  [[ -z "$self" ]] && { _warn "Self id unavailable; falling back to hostname"; self=$(hostname); }
  if docker node update --label-add hostaffin_role=master "$self"; then
    _ok "Node labelled hostaffin_role=master"
  else
    _warn "Could not label node (acceptable in single-node mode)"
  fi
}

step_overlay_network() {
  _hr; _log "Creating overlay network hostaffin_edge"
  if docker network ls --format '{{.Name}}' 2>/dev/null | grep -qx 'hostaffin_edge'; then
    _ok "Network already exists"; return
  fi
  docker network create --driver overlay --attachable hostaffin_edge
  _ok "Network created"
}

step_images() {
  mode_runs_db || return
  _hr; _log "Preparing control-plane + admin-panel images"
  local cp_img="hostaffin/control-plane:latest"
  local ap_img="hostaffin/admin-panel:latest"

  if [[ -n "$GITHUB_TOKEN" ]]; then
    if echo "$GITHUB_TOKEN" \
       | docker login "$GHCR_IMAGE_BASE" -u x-access-token --password-stdin >/dev/null 2>&1; then
      # shellcheck disable=SC2015
      docker pull "${GHCR_IMAGE_BASE}/control-plane:latest" \
        && docker tag "${GHCR_IMAGE_BASE}/control-plane:latest" "$cp_img" \
        || _warn "control-plane pull failed; will build from source"
      # shellcheck disable=SC2015
      docker pull "${GHCR_IMAGE_BASE}/admin-panel:latest" \
        && docker tag "${GHCR_IMAGE_BASE}/admin-panel:latest" "$ap_img" \
        || _warn "admin-panel pull failed; will build from source"
    else
      _warn "GHCR login failed; will build from local source"
    fi
  fi

  if [[ -d "$PROJECT_DIR/control-plane" ]] \
     && ! docker image inspect "$cp_img" >/dev/null 2>&1; then
    _log "Building control-plane from source"
    install_go_if_missing
    ( cd "$PROJECT_DIR/control-plane" && docker build -t "$cp_img" . )
  fi
  if [[ -d "$PROJECT_DIR/admin-panel" ]] \
     && ! docker image inspect "$ap_img" >/dev/null 2>&1; then
    _log "Building admin-panel from source"
    install_node_if_missing
    ( cd "$PROJECT_DIR/admin-panel" && docker build -t "$ap_img" . )
  fi
  _ok "Images prepared"
}

step_compose_stack() {
  mode_runs_db || return
  _hr; _log "Writing docker-compose stack"
  cat >"$PROJECT_DIR/docker-compose.yml" <<'EOF'
services:
  postgres:
    image: postgres:16-alpine
    container_name: hostaffin-postgres
    environment: { POSTGRES_USER: sgtm, POSTGRES_PASSWORD: sgtm, POSTGRES_DB: sgtm }
    volumes: ["pgdata:/var/lib/postgresql/data"]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U sgtm -d sgtm"]
      interval: 5s
      timeout: 5s
      retries: 20

  redis:
    image: redis:7-alpine
    container_name: hostaffin-redis
    healthcheck: { test: ["CMD", "redis-cli", "ping"], interval: 5s, timeout: 3s, retries: 20 }

  clickhouse:
    image: clickhouse/clickhouse-server:24-alpine
    container_name: hostaffin-clickhouse
    environment: { CLICKHOUSE_DB: sgtm, CLICKHOUSE_USER: sgtm, CLICKHOUSE_PASSWORD: sgtm }
    volumes: ["chdata:/var/lib/clickhouse"]
    ulimits: { nofile: { soft: 262144, hard: 262144 } }

  control-plane:
    image: hostaffin/control-plane:latest
    container_name: hostaffin-control-plane
    depends_on:
      postgres:   { condition: service_healthy }
      redis:      { condition: service_healthy }
      clickhouse: { condition: service_started }
    env_file: /etc/hostaffin/hostaffin.env
    ports: ["8080:8080"]
    networks: [hostaffin_edge]

  worker:
    image: hostaffin/control-plane:latest
    container_name: hostaffin-worker
    depends_on:
      postgres: { condition: service_healthy }
      redis:    { condition: service_healthy }
    command: ["/app/worker"]
    env_file: /etc/hostaffin/hostaffin.env
    networks: [hostaffin_edge]

  admin-panel:
    image: hostaffin/admin-panel:latest
    container_name: hostaffin-admin-panel
    depends_on: [control-plane]
    environment:
      NEXT_PUBLIC_CONTROL_PLANE_URL: http://localhost:8080
      CONTROL_PLANE_URL:             http://control-plane:8080
    ports: ["3000:3000"]
    networks: [hostaffin_edge]

networks: { hostaffin_edge: { external: true } }
volumes:  { pgdata: {}, chdata: {} }
EOF
  _ok "Compose stack written"
}

step_deploy() {
  mode_runs_db || return
  _hr; _log "Deploying stack"
  ( cd "$PROJECT_DIR" && docker compose up -d )
  _ok "Stack deployed"
}

step_migrate() {
  mode_runs_db || return
  _hr; _log "Waiting for Postgres"
  local i=0
  until docker exec hostaffin-postgres pg_isready -U sgtm -d sgtm >/dev/null 2>&1; do
    ((i++ > 60)) && { _err "Postgres did not become healthy"; exit 1; }
    sleep 2
  done
  _ok "Postgres ready"
  _log "Running migrations + seed"
  local cpid; cpid=$(docker ps -q -f name=^hostaffin-control-plane$ | head -n1)
  [[ -z "$cpid" ]] && { _err "control-plane container not running"; exit 1; }
  docker exec "$cpid" /app/migrate up
  docker exec "$cpid" /app/seed
  _ok "Migrations + seed applied"
}

step_traefik() {
  mode_runs_edge || return
  _hr; _log "Installing Traefik reverse proxy"
  mkdir -p /etc/traefik /var/log/traefik /letsencrypt
  chmod 700 /letsencrypt
  cat >/etc/traefik/traefik.yml <<'EOF'
api: { dashboard: true, insecure: false }
log:  { level: INFO, format: json }
entryPoints:
  web:       { address: ":80",  http: { redirections: { entryPoint: { to: websecure, scheme: https } } } }
  websecure: { address: ":443" }
providers:
  docker: { swarmMode: true, exposedByDefault: false, network: hostaffin_edge }
certificatesResolvers:
  letsencrypt:
    acme: { email: ops@hostaffin.com, storage: /letsencrypt/acme.json, httpChallenge: { entryPoint: web } }
EOF
  cat >/etc/systemd/system/hostaffin-traefik.service <<'EOF'
[Unit]
Description=Hostaffin Traefik (host network)
After=docker.service
Requires=docker.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=-/usr/bin/docker rm -f hostaffin-traefik
ExecStart=/usr/bin/docker run --rm --name hostaffin-traefik \
  --network host \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v /etc/traefik/traefik.yml:/etc/traefik/traefik.yml:ro \
  -v /letsencrypt:/letsencrypt \
  -v /var/log/traefik:/var/log/traefik \
  traefik:v3.0
ExecStop=/usr/bin/docker stop hostaffin-traefik
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now hostaffin-traefik
  _ok "Traefik installed and running"
}

step_node_agent() {
  mode_runs_edge || return
  _hr; _log "Installing Node Agent"
  local bin=/usr/local/bin/hostaffin-node-agent
  if [[ ! -x "$bin" ]]; then
    if curl -fsSL -o "$bin" "$GHCR_NODE_AGENT_RELEASE"; then
      _ok "Downloaded prebuilt node-agent"
    else
      _warn "Prebuilt unavailable; building from source (Go ${GOLANG_VERSION})"
      install_go_if_missing
      [[ -d "$PROJECT_DIR/node-agent/cmd/agent" ]] || {
        _err "node-agent source not found at $PROJECT_DIR/node-agent/cmd/agent"; exit 1;
      }
      ( cd "$PROJECT_DIR/node-agent" \
          && go build -trimpath -ldflags="-s -w" -o "$bin" ./cmd/agent )
    fi
    chmod 0755 "$bin"
  else
    _ok "Node agent binary already present"
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
  _ok "Node agent installed and running"
}

step_health_check() {
  _hr; _log "Health checks"
  local api_ok=false i
  for i in $(seq 1 20); do
    if curl -fsSL "http://localhost:8080/healthz" >/dev/null 2>&1; then api_ok=true; break; fi
    sleep 2
  done
  # shellcheck disable=SC2015
  $api_ok && _ok "Control plane API healthy" || _warn "API not yet responding (may still be starting)"

  for unit in hostaffin-node-agent hostaffin-traefik; do
    if systemctl is-active --quiet "$unit" 2>/dev/null; then
      _ok "$unit running"
    else
      _warn "$unit not running (expected for MODE != local/master)"
    fi
  done

  docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || true
  _ok "Health check complete"
}

step_summary() {
  local BOLD='\033[1m' GREEN='\033[1;32m' RESET='\033[0m'
  local ip; ip=$(hostname -I 2>/dev/null | awk '{print $1}'); [[ -z "$ip" ]] && ip="<this-host>"
  cat <<EOF

${BOLD}${GREEN}
╔════════════════════════════════════════════════════════════════════╗
║           Hostaffin sGTM Platform — install complete              ║
╚════════════════════════════════════════════════════════════════════╝
${RESET}

Mode:           $MODE
Project dir:    $PROJECT_DIR
Env file:       $ENV_FILE
Admin URL:      http://${ip}:3000
API URL:        http://${ip}:8080
Admin login:    ${ADMIN_EMAIL:-admin@hostaffin.local}
Admin password: $(cat "$ADMIN_PWD_FILE" 2>/dev/null || echo "(see $ENV_FILE)")
Node ID:        $NODE_ID
Node API key:   $(grep '^NODE_API_KEY=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- || echo '(unset)')

Useful commands:
  systemctl status hostaffin-node-agent
  systemctl status hostaffin-traefik
  journalctl -u hostaffin-node-agent -f
  cd $PROJECT_DIR && docker compose logs -f

Log file: $LOG_FILE
EOF
}

# ═════════════════════════════════════════════════════════════════════════
# SECTION 8 — UNINSTALL STEPS
# ═════════════════════════════════════════════════════════════════════════
_uninstall_units=(hostaffin-node-agent.service hostaffin-traefik.service)
_uninstall_unitfiles=(/etc/systemd/system/hostaffin-node-agent.service
                      /etc/systemd/system/hostaffin-traefik.service
                      /etc/systemd/system/traefik.service.d/override.conf)

uninstall_stop_units() {
  _hr; _log "Stopping hostaffin systemd units"
  local u
  for u in "${_uninstall_units[@]}"; do
    if systemctl list-unit-files "$u" >/dev/null 2>&1; then
      run_soft systemctl stop    "$u"
      run_soft systemctl disable "$u"
    else
      _log "  · $u not installed, skipping"
    fi
  done
  _ok "Systemd units stopped"
}

uninstall_remove_units() {
  _hr; _log "Removing systemd unit files"
  local f
  for f in "${_uninstall_unitfiles[@]}"; do
    [[ -e "$f" ]] && run_soft rm -rf "$f"
  done
  run_soft systemctl daemon-reload
  _ok "Systemd unit files removed"
}

uninstall_remove_traefik_container() {
  _hr; _log "Removing Traefik container"
  if command -v docker >/dev/null \
     && docker ps -a --format '{{.Names}}' | grep -qx 'hostaffin-traefik'; then
    run_soft docker rm -f hostaffin-traefik
  fi
  _ok "Traefik container removed"
}

uninstall_tear_compose() {
  mode_runs_db || return
  _hr; _log "Tearing down docker-compose stack"
  if [[ -f "$PROJECT_DIR/docker-compose.yml" ]]; then
    ( cd "$PROJECT_DIR" && run_soft docker compose down --remove-orphans ) || true
  else
    local n
    for n in hostaffin-control-plane hostaffin-worker hostaffin-admin-panel \
             sgtm-postgres sgtm-redis sgtm-clickhouse; do
      docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$n" && run_soft docker rm -f "$n"
    done
  fi
  _ok "Compose stack torn down"
}

uninstall_volumes() {
  $PURGE || { _log "  · Skipping volume removal (use --purge)"; return; }
  _hr; _log "Removing Docker volumes"
  local v
  for v in "${DOCKER_VOLUMES[@]}"; do
    docker volume ls --format '{{.Name}}' 2>/dev/null | grep -qx "$v" && run_soft docker volume rm "$v"
  done
  local pv
  pv=$(docker volume ls --format '{{.Name}}' 2>/dev/null | grep -E '(pgdata|chdata)$' || true)
  for v in $pv; do run_soft docker volume rm "$v"; done
  _ok "Docker volumes removed"
}

uninstall_images() {
  $PURGE || return
  _hr; _log "Removing Hostaffin-built Docker images"
  local img
  while IFS= read -r img; do
    [[ -n "$img" ]] && run_soft docker rmi "$img"
  done < <(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null \
           | grep -E '^(hostaffin/(control-plane|admin-panel))' || true)
  _ok "Images removed"
}

uninstall_node_label() {
  command -v docker >/dev/null || return
  docker info 2>/dev/null | grep -q "Swarm: active" || return
  _hr; _log "Removing hostaffin_role=master label"
  local self
  self=$(docker node ls --format '{{.Self}} {{.ID}}' 2>/dev/null \
         | awk '$1=="true"{print $2; exit}')
  [[ -n "$self" ]] && run_soft docker node update --label-rm hostaffin_role=master "$self"
  _ok "Node label removed"
}

uninstall_overlay() {
  command -v docker >/dev/null || return
  _hr; _log "Removing hostaffin_edge overlay network"
  if docker network ls --format '{{.Name}}' 2>/dev/null | grep -qx 'hostaffin_edge'; then
    run_soft docker network rm hostaffin_edge
  fi
  _ok "Overlay network removed"
}

uninstall_swarm() {
  command -v docker >/dev/null || return
  docker info 2>/dev/null | grep -q "Swarm: active" || { _log "  · Not in a Swarm"; return; }
  _hr; _log "Handling Swarm membership"
  local self
  self=$(docker node ls --format '{{.Self}} {{.ID}}' 2>/dev/null \
         | awk '$1=="true"{print $2; exit}')
  [[ -n "$self" ]] && run_soft docker node update --availability drain "$self"
  $LEAVE_SWARM && { _log "  · --leave-swarm set; NOT executing 'docker swarm leave'"; return; }
  if confirm "Drain and 'docker swarm leave' this node? (other nodes keep quorum)" n; then
    run_soft docker swarm leave
  fi
  _ok "Swarm membership handled"
}

uninstall_workspace() {
  $PURGE || { _log "  · Keeping $PROJECT_DIR (use --purge)"; return; }
  _hr; _log "Removing project workspace $PROJECT_DIR"
  [[ -d "$PROJECT_DIR" ]] && run_soft rm -rf "$PROJECT_DIR"
  _ok "Workspace removed"
}

uninstall_etc() {
  $PURGE || { _log "  · Keeping $ENV_FILE (use --purge)"; return; }
  _hr; _log "Removing /etc/hostaffin"
  [[ -d /etc/hostaffin ]] && run_soft rm -rf /etc/hostaffin
  [[ -f "$ADMIN_PWD_FILE" ]] && run_soft rm -f "$ADMIN_PWD_FILE"
  _ok "/etc/hostaffin removed"
}

uninstall_logs() {
  $PURGE || { _log "  · Keeping $LOG_DIR (use --purge)"; return; }
  _hr; _log "Removing Hostaffin log directories"
  [[ -d "$LOG_DIR" ]]      && run_soft rm -rf "$LOG_DIR"
  [[ -d /var/log/traefik ]] && run_soft rm -rf /var/log/traefik
  [[ -d /letsencrypt ]]    && run_soft rm -rf /letsencrypt
  _ok "Logs removed"
}

uninstall_binary() {
  $PURGE && [[ -x /usr/local/bin/hostaffin-node-agent ]] && {
    _hr; _log "Removing hostaffin-node-agent binary"
    run_soft rm -f /usr/local/bin/hostaffin-node-agent
    _ok "Binary removed"
  }
}

uninstall_sysctl() {
  $KEEP_SYSCTL && { _log "  · Keeping sysctl (--keep-sysctl)"; return; }
  _hr; _log "Removing sysctl overrides"
  if [[ -f /etc/sysctl.d/99-hostaffin.conf ]]; then
    run_soft rm -f /etc/sysctl.d/99-hostaffin.conf
    run_soft sysctl --system
  fi
  _ok "Sysctl overrides removed"
}

uninstall_ulimits() {
  $KEEP_ULIMITS && { _log "  · Keeping ulimits (--keep-ulimits)"; return; }
  _hr; _log "Removing ulimits overrides"
  [[ -f /etc/security/limits.d/99-hostaffin.conf ]] && run_soft rm -f /etc/security/limits.d/99-hostaffin.conf
  _ok "Ulimits overrides removed"
}

uninstall_firewalld() {
  $KEEP_FIREWALL && { _log "  · Keeping firewalld rules (--keep-firewall)"; return; }
  command -v firewall-cmd >/dev/null || return
  _hr; _log "Removing firewalld rules"
  local p
  for p in "${FIREWALL_PORTS[@]}"; do
    run_soft firewall-cmd --permanent --remove-port="$p"
  done
  run_soft firewall-cmd --reload
  _ok "Firewalld rules removed"
}

uninstall_selinux_module() {
  command -v semodule >/dev/null || return
  _hr; _log "Removing SELinux module"
  if semodule -l 2>/dev/null | grep -qx 'hostaffin'; then
    run_soft semodule -r hostaffin
  fi
  _ok "SELinux module processed"
}

uninstall_docker() {
  $KEEP_DOCKER && { _log "  · Keeping Docker (--keep-docker)"; return; }
  command -v docker >/dev/null || return
  _hr; _log "Uninstalling Docker Engine"
  if ! confirm "Remove Docker Engine + Compose plugin? (other workloads on this host will be affected)" n; then
    _log "  · Skipped per user"; return
  fi
  run_soft pm_remove docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras
  _ok "Docker Engine packages removed"
}

uninstall_summary() {
  local BOLD='\033[1m' GREEN='\033[1;32m' RESET='\033[0m'
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

If you also want to re-enable swap that the installer disabled, restore
/etc/fstab from the .bak the installer created.
EOF
}

# ═════════════════════════════════════════════════════════════════════════
# SECTION 9 — HEALTH CHECK
# ═════════════════════════════════════════════════════════════════════════
health_check_run() {
  _hr; _log "Health check"
  local fail=0

  if command -v docker >/dev/null; then
    _ok "Docker installed: $(docker --version)"
    if systemctl is-active --quiet docker 2>/dev/null; then _ok "Docker daemon running"
    else _err "Docker daemon NOT running"; fail=1; fi
  else
    _err "Docker not installed"; fail=1
  fi

  if docker info 2>/dev/null | grep -q "Swarm: active"; then
    _ok "Swarm active"
    local nodes
    nodes=$(docker node ls --format '{{.Hostname}} ({{.Status}})' 2>/dev/null | wc -l)
    _ok "Swarm nodes: $nodes"
  else
    _warn "Swarm not active"
  fi

  for unit in hostaffin-node-agent hostaffin-traefik; do
    if systemctl list-unit-files "$unit.service" >/dev/null 2>&1; then
      if systemctl is-active --quiet "$unit"; then _ok "$unit running"
      else _err "$unit NOT running"; fail=1; fi
    fi
  done

  local port desc
  for entry in "8080/tcp:Control plane API" "3000/tcp:Admin panel" \
               "80/tcp:Traefik HTTP" "443/tcp:Traefik HTTPS" "2377/tcp:Swarm mgmt"; do
    port="${entry%%:*}"; desc="${entry#*:}"
    if ss -tln 2>/dev/null | awk '{print $4}' | grep -qE ":${port}\$|:${port}\b"; then
      _ok "Port $port open ($desc)"
    else
      _warn "Port $port not listening ($desc)"
    fi
  done

  local i
  for i in $(seq 1 10); do
    if curl -fsSL "http://localhost:8080/healthz" >/dev/null 2>&1; then _ok "API /healthz OK"; break; fi
    sleep 2
  done
  if [[ $i -eq 10 ]]; then _warn "API /healthz unreachable"; fi

  local disk
  disk=$(df -P "$PROJECT_DIR" 2>/dev/null | tail -n1 | awk '{print $5}')
  [[ -n "$disk" ]] && _log "Disk usage on $PROJECT_DIR: $disk"

  if [[ $fail -eq 0 ]]; then _ok "Health check: PASS"; else _err "Health check: FAIL ($fail issue(s))"; exit 1; fi
}

# ═════════════════════════════════════════════════════════════════════════
# SECTION 10 — INTERACTIVE WIZARD
# ═════════════════════════════════════════════════════════════════════════
wizard_welcome() {
  ui_clear; ui_banner
  cat <<EOF
${C_BOLD}Welcome!${C_RESET}
This wizard will install the Hostaffin sGTM Platform on this host.
Sensible defaults are provided; press ${C_BOLD}Enter${C_RESET} to accept,
or ${C_BOLD}Ctrl+C${C_RESET} to abort at any time.
EOF
  _hr
}

wizard_ask_timezone() {
  ui_step_banner 1 "Timezone"
  local detected=""
  [[ -f /etc/localtime ]] && detected=$(readlink /etc/localtime 2>/dev/null | sed 's|/usr/share/zoneinfo/||')
  [[ -z "$detected" ]] && detected="UTC"
  local default="${TZ_NAME:-$detected}"
  TZ_NAME=$(ui_prompt "Timezone (Region/City)" "$default")
  if [[ -f "/usr/share/zoneinfo/$TZ_NAME" ]]; then
    ln -sf "/usr/share/zoneinfo/$TZ_NAME" /etc/localtime
  fi
  _ok "Timezone: $TZ_NAME"; ui_step_done
}

wizard_ask_dns() {
  ui_step_banner 2 "Public DNS wildcard"
  local default="${DNS_WILDCARD:-edge.$(hostname -d 2>/dev/null || echo hostaffin.com)}"
  while :; do
    DNS_WILDCARD=$(ui_prompt "DNS wildcard base domain" "$default")
    ui_validate_hostname "$DNS_WILDCARD" && break
    _warn "Not a valid DNS hostname"
  done
  _ok "DNS wildcard: $DNS_WILDCARD"; ui_step_done
}

wizard_ask_mode() {
  ui_step_banner 3 "Install mode"
  local opts=(
    "local          — single-host all-in-one (DB + control plane + Traefik + node agent)"
    "master         — join an existing Swarm as another master node"
    "controlplane   — control plane + DB stack only (no Traefik / node agent)"
  )
  local pick
  pick=$(ui_choose "Select install mode:" "${opts[@]}")
  case "$pick" in
    1) MODE="local" ;; 2) MODE="master" ;; 3) MODE="controlplane" ;;
  esac
  _ok "Mode: $MODE"; ui_step_done
}

wizard_ask_master_join() {
  ui_step_banner 4 "Swarm join details"
  while :; do
    MANAGER_ADDR=$(ui_prompt "Manager address (e.g. 10.0.0.10:2377)" "${MANAGER_ADDR:-127.0.0.1:2377}")
    [[ "$MANAGER_ADDR" =~ ^[A-Za-z0-9._-]+:[0-9]+$ ]] && break
    _warn "Format must be host:port"
  done
  while :; do
    JOIN_TOKEN=$(ui_prompt "Worker join token" "$JOIN_TOKEN")
    [[ -n "$JOIN_TOKEN" ]] && break
    _warn "Join token is required for master mode"
  done
  _ok "Will join $MANAGER_ADDR"; ui_step_done
}

wizard_ask_cp_url() {
  ui_step_banner 4 "Control plane URL"
  local default="${CONTROL_PLANE_URL:-https://cp.${DNS_WILDCARD}}"
  while :; do
    CONTROL_PLANE_URL=$(ui_prompt "Control plane URL" "$default")
    ui_validate_url "$CONTROL_PLANE_URL" && break
    _warn "Must be a valid http(s) URL"
  done
  _ok "Control plane URL: $CONTROL_PLANE_URL"; ui_step_done
}

wizard_ask_admin() {
  ui_step_banner 5 "Admin account"
  local default="${ADMIN_EMAIL:-admin@${DNS_WILDCARD}}"
  ADMIN_EMAIL=$(ui_prompt "Admin email" "$default")
  while :; do
    _log "Leave blank to auto-generate a strong password"
    ADMIN_PASSWORD=$(ui_password "Admin password (input hidden)")
    if [[ -z "$ADMIN_PASSWORD" ]]; then
      ADMIN_PASSWORD=$(openssl rand -base64 18 | tr -d '=+/')
      _ok "Generated admin password"; break
    fi
    if [[ ${#ADMIN_PASSWORD} -ge 10 ]]; then
      local confirm_pw
      confirm_pw=$(ui_password "Confirm admin password")
      [[ "$confirm_pw" == "$ADMIN_PASSWORD" ]] && break
      _warn "Passwords do not match — try again"
    else
      _warn "Password must be at least 10 characters"
    fi
  done
  ui_step_done
}

wizard_ask_optional() {
  ui_step_banner 6 "Optional: image registry"
  GITHUB_TOKEN=$(ui_prompt "GHCR token (blank to skip)" "${GITHUB_TOKEN:-}")
  ui_step_done
}

wizard_ask_advanced() {
  ui_step_banner 7 "Advanced options"
  if ui_confirm "Skip firewall configuration?" "n"; then SKIP_FIREWALL=true; fi
  if ui_confirm "Keep swap enabled (not recommended)?" "n"; then SKIP_SWAP=true; fi
  if [[ "$MODE" == "local" ]]; then
    local default_id
    default_id="master-$(hostname -s | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')-01"
    NODE_ID=$(ui_prompt "Node ID" "${NODE_ID:-$default_id}")
  fi
  ui_step_done
}

wizard_review() {
  ui_step_banner 8 "Review"
  cat <<EOF >&2
${C_BOLD}${C_BCYAN}Please review:${C_RESET}
${C_DIM}────────────────────────────────────────────────${C_RESET}
  Timezone:        $TZ_NAME
  DNS wildcard:    $DNS_WILDCARD
  Mode:            $MODE
EOF
  [[ "$MODE" == "master" ]] && cat <<EOF >&2
  Manager addr:    $MANAGER_ADDR
  Join token:      ${JOIN_TOKEN:0:8}… (truncated)
EOF
  [[ "$MODE" == "local" || "$MODE" == "controlplane" ]] && cat <<EOF >&2
  Control plane:   $CONTROL_PLANE_URL
EOF
  cat <<EOF >&2
  Admin email:     $ADMIN_EMAIL
  Admin password:  $([[ -n "$ADMIN_PASSWORD" ]] && echo "(set, ${#ADMIN_PASSWORD} chars)" || echo "(auto-generate)")
  GHCR token:      $([[ -n "$GITHUB_TOKEN" ]] && echo "(set)" || echo "(none)")
  Skip firewall:   $SKIP_FIREWALL
  Keep swap:       $SKIP_SWAP
${C_DIM}────────────────────────────────────────────────${C_RESET}
EOF
  ui_confirm "Proceed with installation?" "y" || { _err "Aborted."; exit 5; }
  ui_step_done
}

# ═════════════════════════════════════════════════════════════════════════
# SECTION 11 — SUB-COMMAND DRIVERS
# ═════════════════════════════════════════════════════════════════════════
cmd_install() {
  require_root
  require_yum_distro

  mkdir -p "$LOG_DIR" 2>/dev/null || true
  LOG_FILE="$LOG_DIR/install-$(date -u +%Y%m%d%H%M%S).log"
  [[ -w "$LOG_DIR" ]] && exec > >(tee -a "$LOG_FILE") 2>&1

  _log "Hostaffin sGTM Platform installer"
  _log "Mode: $MODE  ·  OS: $PRETTY_NAME $VERSION_ID"
  [[ -n "$CONTROL_PLANE_URL" ]] && _log "Control plane URL: $CONTROL_PLANE_URL"

  if ! $NON_INTERACTIVE; then
    echo
    _warn "This will install Docker, init/join a Swarm, and deploy services."
    confirm "Continue?" || { _err "Aborted."; exit 5; }
  fi

  step_packages
  step_system_tuning
  step_firewalld
  step_selinux
  step_docker
  step_project_layout
  step_env_file
  step_swarm
  step_node_label
  step_overlay_network
  step_images
  step_compose_stack
  step_deploy
  step_traefik
  step_node_agent
  step_migrate
  step_health_check
  step_summary
  _ok "Done."
}

cmd_uninstall() {
  require_root
  pm_detect || true   # uninstall may run on a host where dnf/yum is half-removed

  mkdir -p "$LOG_DIR" 2>/dev/null || true
  LOG_FILE="$LOG_DIR/uninstall-$(date -u +%Y%m%d%H%M%S).log"
  [[ -w "$LOG_DIR" ]] && exec > >(tee -a "$LOG_FILE") 2>&1

  _log "Hostaffin sGTM Platform uninstaller"
  _log "Mode: $MODE"
  $PURGE && _warn "PURGE mode — data directories will be DELETED"

  # PURGE safety: regardless of --non-interactive, require a typed confirmation.
  # This guards against scripted/cron invocations that accidentally pass --purge.
  if $PURGE; then
    echo
    _warn "PURGE will permanently delete:"
    _warn "  - $PROJECT_DIR"
    _warn "  - /etc/hostaffin"
    _warn "  - $LOG_DIR"
    _warn "  - /var/log/traefik"
    _warn "  - /letsencrypt"
    _warn "  - $ADMIN_PWD_FILE"
    _warn "  - all Docker volumes named pgdata / chdata (and any *_pgdata / *_chdata)"
    local confirm_purge
    while :; do
      read -rp "$(printf '\033[1;31m[!!]\033[0m Type DELETE to confirm purge (anything else aborts): ')" confirm_purge
      [[ "$confirm_purge" == "DELETE" ]] && break
      _err "Aborted."; exit 5
    done
  fi

  if ! $NON_INTERACTIVE; then
    echo
    _warn "This will stop and remove Hostaffin services and (with --purge)"
    _warn "configuration. It is NOT destructive to other workloads unless"
    _warn "you also confirm the Docker removal step."
    confirm "Continue with uninstall?" || { _err "Aborted."; exit 5; }
  fi

  uninstall_stop_units
  uninstall_remove_traefik_container
  uninstall_tear_compose
  uninstall_volumes
  uninstall_images
  uninstall_node_label
  uninstall_overlay
  uninstall_swarm
  uninstall_remove_units
  uninstall_workspace
  uninstall_etc
  uninstall_logs
  uninstall_binary
  uninstall_sysctl
  uninstall_ulimits
  uninstall_firewalld
  uninstall_selinux_module
  uninstall_docker
  uninstall_summary
  _ok "Done."
}

cmd_interactive() {
  require_root
  require_yum_distro
  wizard_welcome
  ui_init_steps 8
  wizard_ask_timezone
  wizard_ask_dns
  wizard_ask_mode
  if [[ "$MODE" == "master" ]]; then
    wizard_ask_master_join
  else
    wizard_ask_cp_url
  fi
  wizard_ask_admin
  wizard_ask_optional
  wizard_ask_advanced
  wizard_review

  # Save config if requested
  if [[ -n "$SAVE_CONFIG" ]]; then
    umask 077
    {
      echo "# Hostaffin sGTM Platform — installer answers"
      echo "# Generated $(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo "TZ=$TZ_NAME"
      echo "DNS_WILDCARD=$DNS_WILDCARD"
      echo "MODE=$MODE"
      echo "JOIN_TOKEN=$JOIN_TOKEN"
      echo "MANAGER_ADDR=$MANAGER_ADDR"
      echo "CONTROL_PLANE_URL=$CONTROL_PLANE_URL"
      echo "ADMIN_EMAIL=$ADMIN_EMAIL"
      echo "ADMIN_PASSWORD=$ADMIN_PASSWORD"
      echo "NODE_ID=$NODE_ID"
      echo "NODE_API_KEY=$NODE_API_KEY"
      echo "GITHUB_TOKEN=$GITHUB_TOKEN"
      echo "SKIP_FIREWALL=$SKIP_FIREWALL"
      echo "SKIP_SWAP=$SKIP_SWAP"
    } > "$SAVE_CONFIG"
    chmod 0600 "$SAVE_CONFIG"
    _ok "Saved answers to $SAVE_CONFIG"
  fi

  # Now run the install pipeline with the values the wizard collected.
  NON_INTERACTIVE=true   # sub-steps should not re-prompt
  cmd_install
}

# ═════════════════════════════════════════════════════════════════════════
# SECTION 12 — ENTRY POINT
# ═════════════════════════════════════════════════════════════════════════
main() {
  parse_args "$@"
  load_env_file
  # Validate MODE for every subcommand (was previously only inside cmd_install).
  if [[ "$SUBCOMMAND" != "help" ]]; then
    validate_common
  fi
  # Self-bootstrap AFTER env-file so HOSTAFFIN_INSTALL_URL works.
  self_bootstrap "$@"

  case "$SUBCOMMAND" in
    install)      cmd_install ;;
    uninstall)    cmd_uninstall ;;
    interactive)  cmd_interactive ;;
    health-check) health_check_run ;;
    help)         print_help; exit 0 ;;
    *) _err "Unknown subcommand: $SUBCOMMAND"; print_help; exit 2 ;;
  esac
}

main "$@"
