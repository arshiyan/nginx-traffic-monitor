#!/usr/bin/env bash
# Example plugin — enable via: ./traffic-monitor.sh --plugins enable hello_world

plugin_init() {
  ntm_register_hook before_menu hello_world_before_menu
}

hello_world_before_menu() {
  : # no-op demo hook
}

plugin_run() {
  ntm_title "Hello World Plugin"
  ntm_ok "Plugin system is working."
  ntm_info "Plugin dir: ${NTM_CURRENT_PLUGIN_DIR:-unknown}"
  ntm_info "Copy this folder to create your own plugin."
}

plugin_help() {
  echo "Minimal example plugin for developers."
}
