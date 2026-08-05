#!/usr/bin/env bash
# plugins/10-install-verify

plugin_init() { :; }

plugin_run() {
  ntm_title "Install / Verify"
  if ntm_is_root; then
    ntm_install_traffic_logging
  else
    ntm_warn "Not root — running verify-only checks"
    ntm_verify_installation || true
    ntm_info "Re-run with sudo to install: sudo ./install.sh"
  fi
}

plugin_help() {
  echo "Install nginx traffic log_format and access_log, or verify existing setup."
}
