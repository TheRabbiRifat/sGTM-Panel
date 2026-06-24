#!/usr/bin/env bash
# ───────────────────────────────────────────────────────────────────────
# lib-ui.sh — shared ASCII UI helpers for Hostaffin installers
# Source this from any installer:
#   source "$(dirname "$0")/lib-ui.sh"
# Provides: banners, colors, progress spinners, progress bars, prompts.
# Safe to source multiple times.
# ───────────────────────────────────────────────────────────────────────

# Avoid double-sourcing
[[ -n "${__HOSTAFFIN_LIB_UI_LOADED:-}" ]] && return 0
__HOSTAFFIN_LIB_UI_LOADED=1

# ──────────────────────────── Color / style ─────────────────────────────
# Disable colors if not on a TTY or NO_COLOR is set
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_UNDER=$'\033[4m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'
  C_MAGENTA=$'\033[35m'
  C_CYAN=$'\033[36m'
  C_BRED=$'\033[91m'
  C_BGREEN=$'\033[92m'
  C_BYELLOW=$'\033[93m'
  C_BBLUE=$'\033[94m'
  C_BMAGENTA=$'\033[95m'
  C_BCYAN=$'\033[96m'
else
  C_RESET=; C_BOLD=; C_DIM=; C_UNDER=
  C_RED=; C_GREEN=; C_YELLOW=; C_BLUE=; C_MAGENTA=; C_CYAN=
  C_BRED=; C_BGREEN=; C_BYELLOW=; C_BBLUE=; C_BMAGENTA=; C_BCYAN=
fi

# ──────────────────────────── Logging ───────────────────────────────────
ui_log()   { printf '%s[install]%s %s\n' "$C_BOLD$C_BLUE" "$C_RESET" "$*" >&2; }
ui_ok()    { printf '%s[  ok  ]%s %s\n' "$C_BOLD$C_BGREEN" "$C_RESET" "$*" >&2; }
ui_warn()  { printf '%s[ warn ]%s %s\n' "$C_BOLD$C_BYELLOW" "$C_RESET" "$*" >&2; }
ui_err()   { printf '%s[ err  ]%s %s\n' "$C_BOLD$C_BRED" "$C_RESET" "$*" >&2; }
ui_info()  { printf '%s[ info ]%s %s\n' "$C_BOLD$C_BCYAN" "$C_RESET" "$*" >&2; }
ui_hr()    { printf '\n%s%s%s\n' "$C_DIM" "──────────────────────────────────────────────────────────────────────" "$C_RESET" >&2; }

# ──────────────────────────── Banners ───────────────────────────────────
ui_banner() {
  local version="${HOSTAFFIN_VERSION:-1.0.0}"
  # Big block-letter banner
  printf '%s' "$C_BOLD$C_BCYAN" >&2
  cat <<'BANNER' >&2
   _   _           _     __        _    __ _ _           _
  | | | | ___  ___| |__ / _| ___  | |  / _(_) | ___  ___| |__
  | |_| |/ _ \/ __| '_ \ |_ / _ \ | | | |_| | |/ _ \/ __| '_ \
  |  _  |  __/\__ \ | | |  | (_) || | |  _| | |  __/\__ \ | | |
  |_| |_|\___||___/_| |_|_|  \___/ |_| |_| |_|_|\___||___/_| |_|
BANNER
  printf '%s' "$C_RESET" >&2
  printf '%s                  sGTM Hosting Platform · v%s%s\n' "$C_DIM" "$version" "$C_RESET" >&2
  printf '\n' >&2
}

ui_step_banner() {
  # Used for major wizard sections
  local n="$1"; shift
  local title="$*"
  printf '\n%s╔══ Step %s ══╗%s\n' "$C_BOLD$C_BMAGENTA" "$n" "$C_RESET" >&2
  printf '%s║%s  %s  %s║%s\n' "$C_BOLD$C_BMAGENTA" "$C_RESET" "$title" "$C_BOLD$C_BMAGENTA" "$C_RESET" >&2
  printf '%s╚═══════════════╝%s\n' "$C_BOLD$C_BMAGENTA" "$C_RESET" >&2
}

# ──────────────────────────── Boxed text ────────────────────────────────
# Usage: ui_box "title" "line1" "line2" ...
ui_box() {
  local title="$1"; shift
  local width=70
  local bar; bar=$(printf '═%.0s' $(seq 1 $width))
  printf '%s╔═%s═╗%s\n' "$C_BOLD$C_CYAN" "$bar" "$C_RESET" >&2
  printf '%s║%s  %s%-*s%s  %s║%s\n' \
    "$C_BOLD$C_CYAN" "$C_RESET" "$C_BOLD" $((width-2)) "$title" "$C_RESET" \
    "$C_BOLD$C_CYAN" "$C_RESET" >&2
  printf '%s╠═%s═╣%s\n' "$C_BOLD$C_CYAN" "$bar" "$C_RESET" >&2
  while [[ $# -gt 0 ]]; do
    printf '%s║%s  %-*s  %s║%s\n' \
      "$C_BOLD$C_CYAN" "$C_RESET" $((width-2)) "$1" "$C_BOLD$C_CYAN" "$C_RESET" >&2
    shift
  done
  printf '%s╚═%s═╝%s\n' "$C_BOLD$C_CYAN" "$bar" "$C_RESET" >&2
}

# ──────────────────────────── Prompts ───────────────────────────────────
# ui_prompt "Question" "default" → echoes user input to stdout
ui_prompt() {
  local q="$1"
  local default="${2:-}"
  local ans
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

ui_confirm() {
  local q="$1"
  local default="${2:-y}"
  local ans
  read -rp "$(printf '%s[?]%s %s %s[y/N]%s: ' \
    "$C_BOLD$C_BYELLOW" "$C_RESET" "$q" \
    "$C_DIM" "$C_RESET")" ans
  ans="${ans:-$default}"
  case "${ans,,}" in
    y|yes) return 0 ;;
    *)     return 1 ;;
  esac
}

# ui_choose "Question" "opt1" "opt2" "opt3" → echoes chosen index (1-based)
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
    if [[ -z "$ans" ]]; then ans=1; fi
    if [[ "$ans" =~ ^[0-9]+$ ]] && (( ans >= 1 && ans <= ${#opts[@]} )); then
      printf '%d' "$ans"
      return 0
    fi
    ui_warn "Please enter 1-${#opts[@]}"
  done
}

# ui_password "Prompt" → echoes password (no default)
ui_password() {
  local q="$1"
  local ans
  read -rsp "$(printf '%s[?]%s %s%s: ' \
    "$C_BOLD$C_BYELLOW" "$C_RESET" "$q" "$C_RESET")" ans
  printf '\n' >&2
  printf '%s' "$ans"
}

# ──────────────────────────── Validation ────────────────────────────────
# ui_validate_timezone "Region/City" → returns 0 if valid
ui_validate_timezone() {
  local tz="$1"
  if [[ -z "$tz" ]]; then return 1; fi
  if [[ -f "/usr/share/zoneinfo/$tz" ]]; then return 0; fi
  # If the zoneinfo file isn't there, try a partial match
  local found
  found=$(find /usr/share/zoneinfo -mindepth 2 -maxdepth 2 -type f \
    -name "$(basename "$tz")" 2>/dev/null | head -n1)
  [[ -n "$found" ]] && return 0
  return 1
}

# ui_validate_hostname "host.example.com" → returns 0 if valid DNS name
ui_validate_hostname() {
  local h="$1"
  [[ -z "$h" ]] && return 1
  [[ ${#h} -le 253 ]] || return 1
  [[ "$h" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$ ]]
}

# ui_validate_url "https://..." → 0 if valid http(s) URL
ui_validate_url() {
  local u="$1"
  [[ "$u" =~ ^https?://[A-Za-z0-9._-]+(:[0-9]+)?(/.*)?$ ]]
}

# ──────────────────────────── Progress ──────────────────────────────────
# Spinner state
__UI_SPINNER_PID=""
__UI_SPINNER_MSG=""

__ui_spinner_frames=( '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏' )

__ui_spinner_run() {
  local i=0
  local frames=( "${__UI_SPINNER_FRAMES[@]:-${__ui_spinner_frames[@]}}" )
  while :; do
    local f="${frames[$((i % ${#frames[@]}))]}"
    printf '\r%s%s%s %s' \
      "$C_BOLD$C_BCYAN" "$f" "$C_RESET" "$__UI_SPINNER_MSG" >&2
    i=$((i+1))
    sleep 0.1
  done
}

# ui_progress_start "label" → starts spinner in background
ui_progress_start() {
  __UI_SPINNER_MSG="$1"
  # If not a TTY, fall back to a simple log line
  if [[ ! -t 2 ]]; then
    ui_log "$1..."
    return 0
  fi
  __ui_spinner_run &
  __UI_SPINNER_PID=$!
  disown "$__UI_SPINNER_PID" 2>/dev/null || true
}

# ui_progress_done "final message" → stops spinner, prints success
ui_progress_done() {
  local msg="${1:-done}"
  if [[ -n "$__UI_SPINNER_PID" ]] && kill -0 "$__UI_SPINNER_PID" 2>/dev/null; then
    kill "$__UI_SPINNER_PID" 2>/dev/null || true
    wait "$__UI_SPINNER_PID" 2>/dev/null || true
  fi
  __UI_SPINNER_PID=""
  # Erase spinner line
  if [[ -t 2 ]]; then
    printf '\r%*s\r' "$(tput cols 2>/dev/null || echo 80)" "" >&2
  fi
  ui_ok "$msg"
}

# ui_progress_fail "error message" → stops spinner, prints error
ui_progress_fail() {
  local msg="$1"
  if [[ -n "$__UI_SPINNER_PID" ]] && kill -0 "$__UI_SPINNER_PID" 2>/dev/null; then
    kill "$__UI_SPINNER_PID" 2>/dev/null || true
    wait "$__UI_SPINNER_PID" 2>/dev/null || true
  fi
  __UI_SPINNER_PID=""
  if [[ -t 2 ]]; then
    printf '\r%*s\r' "$(tput cols 2>/dev/null || echo 80)" "" >&2
  fi
  ui_err "$msg"
}

# ui_progress_step "label" "command..." → runs cmd with spinner
# Sets EXIT_CODE in the caller's scope.
ui_progress_step() {
  local label="$1"; shift
  ui_progress_start "$label"
  if "$@" >/tmp/hostaffin-step.out 2>&1; then
    ui_progress_done "$label"
    return 0
  else
    local rc=$?
    ui_progress_fail "$label (exit $rc)"
    if [[ -s /tmp/hostaffin-step.out ]]; then
      printf '%s%s%s\n' "$C_DIM" "$(tail -n 30 /tmp/hostaffin-step.out)" "$C_RESET" >&2
    fi
    return $rc
  fi
}

# ──────────────────────────── Progress bar ──────────────────────────────
# ui_progress_bar N M "label" → prints bar at N/M
ui_progress_bar() {
  local cur="$1" tot="$2" label="${3:-}"
  local width=40
  local pct=$(( cur * 100 / (tot > 0 ? tot : 1) ))
  local filled=$(( cur * width / (tot > 0 ? tot : 1) ))
  local empty=$(( width - filled ))
  # Use unicode block chars on capable terminals; fall back to ASCII.
  local block_filled block_empty
  if [[ -t 2 ]] && [[ "${LANG:-}${LC_ALL:-}" =~ UTF-8|utf8 ]]; then
    block_filled="█"; block_empty="░"
  else
    block_filled="#"; block_empty="-"
  fi
  local bar_filled; bar_filled=$(printf "${block_filled}%.0s" $(seq 1 $filled 2>/dev/null) 2>/dev/null)
  local bar_empty; bar_empty=$(printf "${block_empty}%.0s" $(seq 1 $empty 2>/dev/null) 2>/dev/null)
  printf '\r%s[%s%s%s] %3d%% %s' \
    "$C_DIM" \
    "$C_BGREEN" "$bar_filled" "$C_DIM" \
    "$pct" \
    "$label" >&2
}

# ui_total_steps N → sets the total for the wizard
__UI_TOTAL_STEPS=0
__UI_CURRENT_STEP=0
ui_init_steps() { __UI_TOTAL_STEPS="$1"; __UI_CURRENT_STEP=0; }
ui_step_done()  {
  __UI_CURRENT_STEP=$(( __UI_CURRENT_STEP + 1 ))
  ui_progress_bar "$__UI_CURRENT_STEP" "$__UI_TOTAL_STEPS" "complete"
  if (( __UI_CURRENT_STEP == __UI_TOTAL_STEPS )); then
    printf '\n' >&2
  fi
}

# ──────────────────────────── Misc ──────────────────────────────────────
# ui_clear_line
ui_clear_line() {
  if [[ -t 2 ]]; then
    printf '\r%*s\r' "$(tput cols 2>/dev/null || echo 80)" "" >&2
  fi
}

# ui_centered "text" → prints centered text
ui_centered() {
  local cols
  cols=$(tput cols 2>/dev/null || echo 80)
  local pad=$(( (cols - ${#1}) / 2 ))
  [[ $pad -lt 0 ]] && pad=0
  printf '%*s%s\n' "$pad" "" "$1" >&2
}
