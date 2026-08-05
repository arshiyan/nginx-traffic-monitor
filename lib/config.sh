#!/usr/bin/env bash
# config.sh — load defaults and optional overrides

[ -n "${NTM_CONFIG_LOADED:-}" ] && return 0
NTM_CONFIG_LOADED=1

# NTM_ROOT must be set by the caller before sourcing this file.
if [ -z "${NTM_ROOT:-}" ]; then
  NTM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

NTM_CONFIG_FILE="${NTM_CONFIG_FILE:-${NTM_ROOT}/config/defaults.conf}"
NTM_PLUGINS_ENABLED_FILE="${NTM_PLUGINS_ENABLED_FILE:-${NTM_ROOT}/config/plugins.enabled}"
NTM_PLUGINS_DIR="${NTM_PLUGINS_DIR:-${NTM_ROOT}/plugins}"

ntm_load_config() {
  if [ -f "$NTM_CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    . "$NTM_CONFIG_FILE"
  else
    ntm_warn "Config not found: $NTM_CONFIG_FILE — using built-in defaults"
  fi

  : "${NTM_APP_NAME:=Nginx Traffic Monitor}"
  : "${NTM_APP_VERSION:=1.0.0}"
  : "${NTM_TRAFFIC_LOG:=/var/log/nginx/traffic.log}"
  : "${NTM_BACKUP_DIR:=/var/backups/nginx-traffic-monitor}"
  : "${NTM_LOG_FORMAT_NAME:=traffic}"
  : "${NTM_TOP_N:=20}"
  : "${NTM_EXPORT_DIR:=/tmp/nginx-traffic-monitor}"
  : "${NTM_SAMPLE_LOG:=samples/traffic.log.sample}"

  if [ -z "${NTM_LOG_FORMAT_BODY:-}" ]; then
    NTM_LOG_FORMAT_BODY='$time_iso8601 $remote_addr $host $status $request_method "$request_uri" $body_bytes_sent'
  fi
}

# Return effective traffic log path (real log, or sample for demo)
ntm_effective_log() {
  if [ -n "${NTM_FORCE_SAMPLE:-}" ]; then
    ntm_resolve_path "$NTM_SAMPLE_LOG"
    return 0
  fi
  if [ -r "$NTM_TRAFFIC_LOG" ]; then
    printf '%s' "$NTM_TRAFFIC_LOG"
    return 0
  fi
  local sample
  sample="$(ntm_resolve_path "$NTM_SAMPLE_LOG")"
  if [ -r "$sample" ]; then
    ntm_warn "Live log not readable ($NTM_TRAFFIC_LOG) — using sample: $sample" >&2
    printf '%s' "$sample"
    return 0
  fi
  printf '%s' "$NTM_TRAFFIC_LOG"
}
