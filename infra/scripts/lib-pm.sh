#!/usr/bin/env bash
# ───────────────────────────────────────────────────────────────────────
# lib-pm.sh — YUM-family package manager detection + helpers
# ───────────────────────────────────────────────────────────────────────
# Source from any installer script:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib-pm.sh"
#
# Detects whether the host uses `dnf` (modern, RHEL 8+/Fedora/CentOS
# Stream/Alma/Rocky/Oracle 8+/Amazon Linux 2023) or `yum` (legacy,
# RHEL 7/CentOS 7/Amazon Linux 2) and exposes wrapper functions so the
# rest of the installer does not need to know which is available.
#
# Public functions:
#   pm_detect               — detect PM, set $PM_GLOBAL, no-op if already set
#   pm_install <pkgs…>      — install packages, respects $PM_GLOBAL
#   pm_remove <pkgs…>       — remove packages
#   pm_addrepo <url>        — add a yum repo from a URL (uses dnf config-manager
#                             on dnf, falls back to repo-file drop on yum)
#   pm_repo_install <repo> <pkgs…>
#                            — enable a repo (or dnf config-manager add-repo)
#                              and install the listed packages from it
#
# Environment overrides:
#   HOSTAFFIN_PM=dnf|yum    — force a specific PM (skip auto-detect)
# ───────────────────────────────────────────────────────────────────────

set -euo pipefail
IFS=$'\n\t'

# ──────────────────────────── Detection ──────────────────────────────────
PM_GLOBAL="${PM_GLOBAL:-${HOSTAFFIN_PM:-}}"

pm_detect() {
  if [[ -n "$PM_GLOBAL" ]]; then
    if ! command -v "$PM_GLOBAL" >/dev/null 2>&1; then
      echo "lib-pm.sh: HOSTAFFIN_PM=$PM_GLOBAL was requested but not found in PATH" >&2
      return 1
    fi
    return 0
  fi
  if command -v dnf >/dev/null 2>&1; then
    PM_GLOBAL="dnf"
  elif command -v yum >/dev/null 2>&1; then
    PM_GLOBAL="yum"
  else
    echo "lib-pm.sh: neither dnf nor yum was found in PATH" >&2
    return 1
  fi
  export PM_GLOBAL
}

# Auto-detect on source so callers can just use $PM_GLOBAL directly.
pm_detect || true

# ──────────────────────────── Wrappers ───────────────────────────────────
pm_install() {
  pm_detect
  case "$PM_GLOBAL" in
    dnf) dnf -y install "$@" ;;
    yum) yum -y install "$@" ;;
    *)   echo "lib-pm.sh: unsupported PM '$PM_GLOBAL'" >&2; return 1 ;;
  esac
}

pm_remove() {
  pm_detect
  case "$PM_GLOBAL" in
    dnf) dnf -y remove "$@" ;;
    yum) yum -y remove "$@" ;;
    *)   echo "lib-pm.sh: unsupported PM '$PM_GLOBAL'" >&2; return 1 ;;
  esac
}

pm_addrepo() {
  local url="$1"
  pm_detect
  case "$PM_GLOBAL" in
    dnf)
      pm_install dnf-plugins-core >/dev/null 2>&1 || true
      dnf config-manager --add-repo "$url"
      ;;
    yum)
      # yum-utils provides repo-file management; fall back to dropping a
      # .repo file into /etc/yum.repos.d/ if yum-config-manager is missing.
      pm_install yum-utils >/dev/null 2>&1 || true
      if command -v yum-config-manager >/dev/null 2>&1; then
        yum-config-manager --add-repo "$url"
      else
        local fname="/etc/yum.repos.d/$(basename "${url%%\?*}")"
        curl -fsSL "$url" -o "$fname"
      fi
      ;;
    *)
      echo "lib-pm.sh: unsupported PM '$PM_GLOBAL'" >&2
      return 1
      ;;
  esac
}

pm_repo_install() {
  local repo_url="$1"; shift
  pm_detect
  case "$PM_GLOBAL" in
    dnf)
      pm_install dnf-plugins-core >/dev/null 2>&1 || true
      dnf config-manager --add-repo "$repo_url" >/dev/null
      dnf -y install "$@"
      ;;
    yum)
      pm_install yum-utils >/dev/null 2>&1 || true
      if command -v yum-config-manager >/dev/null 2>&1; then
        yum-config-manager --add-repo "$repo_url" >/dev/null
      else
        local fname="/etc/yum.repos.d/$(basename "${repo_url%%\?*}")"
        curl -fsSL "$repo_url" -o "$fname"
      fi
      yum -y install "$@"
      ;;
    *)
      echo "lib-pm.sh: unsupported PM '$PM_GLOBAL'" >&2
      return 1
      ;;
  esac
}