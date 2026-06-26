#!/usr/bin/env bash
# ───────────────────────────────────────────────────────────────────────
# Hostaffin sGTM Platform — One-shot, token-safe installer
# ───────────────────────────────────────────────────────────────────────
#
# This wrapper:
#   • Downloads the canonical installer + lib-pm.sh + lib-ui.sh into a
#     private working dir on the target host (so they run from disk and
#     BASH_SOURCE[0] resolves correctly — no piped-stdin crash).
#   • Passes tokens as environment variables loaded from a 0600 env-file,
#     so they NEVER appear on the command line and are not visible in
#     `ps` / `/proc/*/cmdline` while the installer runs.
#   • Cleans up the working dir on exit (success or failure).
#   • Forces token-bearing variables to be marked read-only inside the
#     installer process to limit accidental echoing.
#   • Verifies installer checksums against an embedded SHA-256 manifest
#     before executing.
#
# Usage:
#   # 1. Put secrets in a 0600 file (NEVER on the command line):
#   sudo install -m 0600 /dev/null /etc/hostaffin/install.env
#   sudo vi /etc/hostaffin/install.env
#     # HOSTAFFIN_MODE=local
#     # HOSTAFFIN_JOIN_TOKEN=...
#     # HOSTAFFIN_GITHUB_TOKEN=...
#     # ... etc
#
#   # 2. Run the wrapper, pointing at that env file:
#   sudo /usr/local/bin/hostaffin-install --env-file /etc/hostaffin/install.env
#
#   # Or, fully non-interactive single command (tokens in env-file):
#   sudo /usr/local/bin/hostaffin-install \
#        --env-file /etc/hostaffin/install.env --non-interactive
#
# Exit codes: same as install-yum.sh
# ───────────────────────────────────────────────────────────────────────

set -euo pipefail
IFS=$'\n\t'

REPO_BASE="${HOSTAFFIN_REPO_BASE:-https://raw.githubusercontent.com/TheRabbiRifat/sGTM-Panel/main/infra/scripts}"
INSTALL_BIN_NAME="install-yum.sh"
LIB_PM_NAME="lib-pm.sh"
LIB_UI_NAME="lib-ui.sh"

ENV_FILE=""
ASSUME_YES=false
WORK_DIR=""

cleanup() {
  local code=$?
  if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
    # shred best-effort, then remove. Falls back to rm if shred is absent.
    if command -v shred >/dev/null 2>&1; then
      find "$WORK_DIR" -type f -exec shred -u {} + 2>/dev/null || true
    fi
    rm -rf -- "$WORK_DIR" 2>/dev/null || true
  fi
  exit "$code"
}
trap cleanup EXIT INT TERM

die()  { printf '\033[1;31m[fatal]\033[0m %s\n' "$*" >&2; exit 1; }
info() { printf '\033[1;34m[info ]\033[0m %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m[ ok  ]\033[0m %s\n' "$*" >&2; }

# ─────────────────────────── Pre-flight ─────────────────────────────────
[[ $EUID -eq 0 ]] || die "Must be run as root (use sudo)."

# ─────────────────────────── CLI flags ─────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)        ENV_FILE="$2"; shift 2 ;;
    --repo-base)       REPO_BASE="$2"; shift 2 ;;
    -y|--yes|--assume-yes) ASSUME_YES=true; shift ;;
    -h|--help)
      sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

# ─────────────────────────── Env file handling ──────────────────────────
# Tokens must be in an env-file (mode 0600), NEVER on the command line.
# We refuse to read env-files that are group/world readable to avoid
# leaking secrets across users on shared hosts.
if [[ -z "$ENV_FILE" ]]; then
  die "Refusing to run with secrets on the command line.
Provide --env-file /etc/hostaffin/install.env (mode 0600) containing
HOSTAFFIN_* variables. Example file:

    HOSTAFFIN_MODE=local
    HOSTAFFIN_JOIN_TOKEN=...
    HOSTAFFIN_NODE_ID=...
    HOSTAFFIN_NODE_API_KEY=...
    HOSTAFFIN_GITHUB_TOKEN=...
"
fi

[[ -f "$ENV_FILE" ]] || die "Env file not found: $ENV_FILE"
FILE_MODE="$(stat -c '%a' "$ENV_FILE" 2>/dev/null || stat -f '%Lp' "$ENV_FILE" 2>/dev/null || echo "?")"
case "$FILE_MODE" in
  600|400) ;;  # ok
  *) die "Env file $ENV_FILE has insecure mode ($FILE_MODE). Run:
    sudo chmod 0600 '$ENV_FILE' && sudo chown root:root '$ENV_FILE'" ;;
esac

# Load env into a clean namespace. We do NOT export until AFTER
# validation so a malformed file can't half-execute the installer.
declare -A LOADED_ENV=()
while IFS='=' read -r key val; do
  # Skip blanks and comments.
  [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
  # Strip optional surrounding quotes from value.
  val="${val%\"}"; val="${val#\"}"
  val="${val%\'}"; val="${val#\'}"
  LOADED_ENV["$key"]="$val"
done < <(grep -E '^[[:space:]]*HOSTAFFIN_[A-Z0-9_]+=' "$ENV_FILE" || true)

# Allowlist: only HOSTAFFIN_* vars may be passed through.
for key in "${!LOADED_ENV[@]}"; do
  if [[ ! "$key" =~ ^HOSTAFFIN_[A-Z0-9_]+$ ]]; then
    die "Refusing non-HOSTAFFIN_ var in env file: $key"
  fi
done

# Require the basics.
: "${LOADED_ENV[HOSTAFFIN_MODE]:=local}"
[[ "${LOADED_ENV[HOSTAFFIN_MODE]}" =~ ^(local|master|controlplane)$ ]] \
  || die "HOSTAFFIN_MODE must be local|master|controlplane (got '${LOADED_ENV[HOSTAFFIN_MODE]}')."

# If join token or api key is set, file must be readable only by root.
# (We already enforced 0600 above, so we're good.)

# ─────────────────────────── Working dir ───────────────────────────────
WORK_DIR="$(mktemp -d -t hostaffin-install-XXXXXX)"
chmod 0700 "$WORK_DIR"
info "Working directory: $WORK_DIR"

# ─────────────────────────── Fetch installer bits ──────────────────────
fetch() {
  local name="$1" url="$2"
  info "Fetching $name"
  # -f fail on HTTP errors, -s silent, -S show errors, -L follow redirects
  if ! curl -fsSL --proto '=https' --tlsv1.2 -o "$WORK_DIR/$name" "$url"; then
    die "Failed to download $name from $url"
  fi
  chmod 0600 "$WORK_DIR/$name"
}

fetch "$INSTALL_BIN_NAME" "$REPO_BASE/$INSTALL_BIN_NAME"
fetch "$LIB_PM_NAME"       "$REPO_BASE/$LIB_PM_NAME"
fetch "$LIB_UI_NAME"       "$REPO_BASE/$LIB_UI_NAME"

# ─────────────────────────── Verify checksums ──────────────────────────
# Hard-coded SHA-256 manifest. Update these whenever you bump a script
# upstream. This prevents a MITM from injecting a malicious installer
# even if TLS is somehow stripped.
#
# Regenerate with:  sha256sum install-yum.sh lib-pm.sh lib-ui.sh
EXPECTED_SHA_INSTALL_YUM="753b578552d08cdf5ef76a46592bb5f517e3a2805534a12518bdda6bad73afab"
EXPECTED_SHA_LIB_PM="b00424e69c1074ae048cf0f10e5b3c853b2166afa9a5531ef28b7672882e4136"
EXPECTED_SHA_LIB_UI="b47ea36f0ac8e68ce8f240ae88833fa775b146c9c4d3d7ef2c745c0f6880b2d0"
# If any expected hash is empty, refuse to run (fail closed).
if [[ -z "$EXPECTED_SHA_INSTALL_YUM" || -z "$EXPECTED_SHA_LIB_PM" || -z "$EXPECTED_SHA_LIB_UI" ]]; then
  die "Checksum manifest is empty in $0. Refusing to run unverified installer.
Update EXPECTED_SHA_* values with: sha256sum $INSTALL_BIN_NAME $LIB_PM_NAME $LIB_UI_NAME"
fi

verify_sha() {
  local file="$1" expected="$2" name="$3"
  local got
  got="$(sha256sum "$file" | awk '{print $1}')"
  if [[ "$got" != "$expected" ]]; then
    die "Checksum mismatch for $name.
  expected: $expected
       got: $got
Refusing to run. The upstream file may have changed — re-pin the hash."
  fi
}

verify_sha "$WORK_DIR/$INSTALL_BIN_NAME" "$EXPECTED_SHA_INSTALL_YUM" "$INSTALL_BIN_NAME"
verify_sha "$WORK_DIR/$LIB_PM_NAME"       "$EXPECTED_SHA_LIB_PM"       "$LIB_PM_NAME"
verify_sha "$WORK_DIR/$LIB_UI_NAME"       "$EXPECTED_SHA_LIB_UI"       "$LIB_UI_NAME"
ok "All installer files verified."

# ─────────────────────────── Run installer ─────────────────────────────
chmod 0700 "$WORK_DIR"
info "Launching installer with mode=${LOADED_ENV[HOSTAFFIN_MODE]}"

# Export ONLY the allowlisted vars. Mark token-bearing ones readonly
# so any accidental `echo $HOSTAFFIN_GITHUB_TOKEN` later is at least
# constrained to a child process.
export HOSTAFFIN_MODE="${LOADED_ENV[HOSTAFFIN_MODE]}"
[[ -n "${LOADED_ENV[HOSTAFFIN_JOIN_TOKEN]:-}"        ]] && { export HOSTAFFIN_JOIN_TOKEN="${LOADED_ENV[HOSTAFFIN_JOIN_TOKEN]}";        readonly HOSTAFFIN_JOIN_TOKEN; }
[[ -n "${LOADED_ENV[HOSTAFFIN_MANAGER_ADDR]:-}"      ]] && { export HOSTAFFIN_MANAGER_ADDR="${LOADED_ENV[HOSTAFFIN_MANAGER_ADDR]}";      readonly HOSTAFFIN_MANAGER_ADDR; }
[[ -n "${LOADED_ENV[HOSTAFFIN_CONTROL_PLANE_URL]:-}" ]] && { export HOSTAFFIN_CONTROL_PLANE_URL="${LOADED_ENV[HOSTAFFIN_CONTROL_PLANE_URL]}"; readonly HOSTAFFIN_CONTROL_PLANE_URL; }
[[ -n "${LOADED_ENV[HOSTAFFIN_NODE_ID]:-}"           ]] && { export HOSTAFFIN_NODE_ID="${LOADED_ENV[HOSTAFFIN_NODE_ID]}";           readonly HOSTAFFIN_NODE_ID; }
[[ -n "${LOADED_ENV[HOSTAFFIN_NODE_API_KEY]:-}"      ]] && { export HOSTAFFIN_NODE_API_KEY="${LOADED_ENV[HOSTAFFIN_NODE_API_KEY]}";      readonly HOSTAFFIN_NODE_API_KEY; }
[[ -n "${LOADED_ENV[HOSTAFFIN_GITHUB_TOKEN]:-}"      ]] && { export HOSTAFFIN_GITHUB_TOKEN="${LOADED_ENV[HOSTAFFIN_GITHUB_TOKEN]}";      readonly HOSTAFFIN_GITHUB_TOKEN; }
[[ -n "${LOADED_ENV[HOSTAFFIN_PM]:-}"                ]] &&   export HOSTAFFIN_PM="${LOADED_ENV[HOSTAFFIN_PM]}"

ARGS=(--mode "${LOADED_ENV[HOSTAFFIN_MODE]}")
[[ "${ASSUME_YES}" == "true" ]] && ARGS+=(--non-interactive)

# Unset tokens from this shell's env so a later `env` dump doesn't leak.
# (The readonly exports above still let the child installer see them,
# but they vanish as soon as the child exits.)
bash "$WORK_DIR/$INSTALL_BIN_NAME" "${ARGS[@]}"
RC=$?

# Best-effort scrub of env from this process.
unset HOSTAFFIN_JOIN_TOKEN HOSTAFFIN_MANAGER_ADDR HOSTAFFIN_CONTROL_PLANE_URL \
      HOSTAFFIN_NODE_ID HOSTAFFIN_NODE_API_KEY HOSTAFFIN_GITHUB_TOKEN \
      HOSTAFFIN_MODE HOSTAFFIN_PM 2>/dev/null || true

exit "$RC"
