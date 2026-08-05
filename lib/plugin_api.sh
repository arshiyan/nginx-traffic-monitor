#!/usr/bin/env bash
# plugin_api.sh — helpers exposed to plugins

[ -n "${NTM_PLUGIN_API_LOADED:-}" ] && return 0
NTM_PLUGIN_API_LOADED=1

# Current plugin context (set by loader while sourcing)
NTM_CURRENT_PLUGIN_ID=""
NTM_CURRENT_PLUGIN_DIR=""

# Convenience wrappers already exist in registry/hooks; this file documents the API
# and provides plugin-scoped helpers.

ntm_plugin_data_dir() {
  printf '%s/data' "${NTM_CURRENT_PLUGIN_DIR}"
}

ntm_plugin_file() {
  printf '%s/%s' "${NTM_CURRENT_PLUGIN_DIR}" "$1"
}
