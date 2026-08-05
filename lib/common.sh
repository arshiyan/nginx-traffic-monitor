#!/usr/bin/env bash
# common.sh — shared helpers: colors, messaging, terminal width, root checks

# Prevent double-sourcing
[ -n "${NTM_COMMON_LOADED:-}" ] && return 0
NTM_COMMON_LOADED=1

# ---------------------------------------------------------------------------
# Colors (respect NO_COLOR and non-TTY)
# ---------------------------------------------------------------------------
ntm_init_colors() {
  if [ -n "${NO_COLOR:-}" ] || [ ! -t 1 ]; then
    C_RESET=""
    C_BOLD=""
    C_DIM=""
    C_RED=""
    C_GREEN=""
    C_YELLOW=""
    C_BLUE=""
    C_CYAN=""
    C_MAGENTA=""
    C_WHITE=""
    return 0
  fi
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'
  C_CYAN=$'\033[36m'
  C_MAGENTA=$'\033[35m'
  C_WHITE=$'\033[37m'
}

ntm_term_width() {
  local w
  w="${COLUMNS:-}"
  if [ -z "$w" ] && command -v tput >/dev/null 2>&1; then
    w="$(tput cols 2>/dev/null || true)"
  fi
  if [ -z "$w" ] || [ "$w" -lt 40 ] 2>/dev/null; then
    w=80
  fi
  printf '%s' "$w"
}

ntm_hr() {
  local width ch i
  width="$(ntm_term_width)"
  ch="${1:--}"
  i=0
  while [ "$i" -lt "$width" ]; do
    printf '%s' "$ch"
    i=$((i + 1))
  done
  printf '\n'
}

ntm_info()    { printf '%s[INFO]%s %s\n' "${C_CYAN}" "${C_RESET}" "$*"; }
ntm_ok()      { printf '%s[OK]%s %s\n' "${C_GREEN}" "${C_RESET}" "$*"; }
ntm_warn()    { printf '%s[WARN]%s %s\n' "${C_YELLOW}" "${C_RESET}" "$*"; }
ntm_error()   { printf '%s[ERROR]%s %s\n' "${C_RED}" "${C_RESET}" "$*" >&2; }
ntm_title() {
  printf '\n%s%s%s\n' "${C_BOLD}${C_BLUE}" "$*" "${C_RESET}"
  ntm_hr "="
}

ntm_require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    ntm_error "This operation requires root privileges. Try: sudo $0"
    return 1
  fi
  return 0
}

ntm_is_root() {
  [ "$(id -u)" -eq 0 ]
}

# Human-readable byte size
ntm_human_bytes() {
  awk -v b="${1:-0}" 'BEGIN {
    if (b < 0) b = 0
    split("B KB MB GB TB PB", u, " ")
    i = 1
    while (b >= 1024 && i < 6) { b /= 1024; i++ }
    if (i == 1) printf "%d %s", b, u[i]
    else printf "%.2f %s", b, u[i]
  }'
}

ntm_timestamp() {
  date '+%Y%m%d-%H%M%S'
}

ntm_iso_now() {
  date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z'
}

# Pause for interactive menus
ntm_pause() {
  printf '\n%sPress Enter to continue...%s' "${C_DIM}" "${C_RESET}"
  # shellcheck disable=SC2162
  read -r _ || true
}

ntm_confirm() {
  local prompt reply
  prompt="${1:-Are you sure? [y/N]} "
  printf '%s' "$prompt"
  # shellcheck disable=SC2162
  read -r reply || true
  case "$reply" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

# Resolve path relative to NTM_ROOT when not absolute
ntm_resolve_path() {
  local p="$1"
  case "$p" in
    /*) printf '%s' "$p" ;;
    *)  printf '%s/%s' "${NTM_ROOT}" "$p" ;;
  esac
}

ntm_init_colors
