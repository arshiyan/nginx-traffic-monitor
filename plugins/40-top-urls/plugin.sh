#!/usr/bin/env bash
plugin_init() { :; }
plugin_run() {
  local period="${NTM_CLI_PERIOD:-today}"
  ntm_title "Top URLs — ${period}"
  ntm_top_field "$period" url
}
