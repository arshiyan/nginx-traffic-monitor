#!/usr/bin/env bash
# install.sh — install / configure Nginx traffic logging
# Usage: sudo ./install.sh [--verify-only]

set -eu

NTM_ROOT="$(cd "$(dirname "$0")" && pwd)"
export NTM_ROOT

# shellcheck disable=SC1091
. "${NTM_ROOT}/lib/common.sh"
# shellcheck disable=SC1091
. "${NTM_ROOT}/lib/config.sh"
ntm_load_config
# shellcheck disable=SC1091
. "${NTM_ROOT}/lib/hooks.sh"
# shellcheck disable=SC1091
. "${NTM_ROOT}/lib/plugin_registry.sh"
# shellcheck disable=SC1091
. "${NTM_ROOT}/lib/plugin_api.sh"
# shellcheck disable=SC1091
. "${NTM_ROOT}/lib/plugin_loader.sh"
# shellcheck disable=SC1091
. "${NTM_ROOT}/lib/nginx.sh"
# shellcheck disable=SC1091
. "${NTM_ROOT}/lib/parse.sh"

ntm_load_all_plugins

case "${1:-}" in
  --verify-only|--verify)
    ntm_title "${NTM_APP_NAME} — Verify"
    ntm_verify_installation
    exit $?
    ;;
  -h|--help)
    cat <<EOF
Usage: sudo ./install.sh [--verify-only]

Detects nginx, backs up nginx.conf, installs log_format "${NTM_LOG_FORMAT_NAME}",
appends access_log directives (without duplicates), validates with nginx -t,
and reloads nginx. On failure, automatically rolls back the backup.
EOF
    exit 0
    ;;
esac

ntm_title "${NTM_APP_NAME} — Installer"
ntm_install_traffic_logging
exit $?
