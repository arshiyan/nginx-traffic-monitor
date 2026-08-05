#!/usr/bin/env bash
# traffic-monitor.sh — interactive menu + non-interactive CLI
# Usage: ./traffic-monitor.sh [options]

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

NTM_CLI_PERIOD="${NTM_CLI_PERIOD:-today}"
NTM_CLI_OUT="${NTM_CLI_OUT:-}"
NTM_CLI_FORMAT="${NTM_CLI_FORMAT:-html}"

ntm_load_all_plugins

ntm_print_banner() {
  local w
  w="$(ntm_term_width)"
  printf '\n'
  ntm_hr "="
  printf '%s%s%s\n' "${C_BOLD}${C_CYAN}" "  ${NTM_APP_NAME} v${NTM_APP_VERSION}" "${C_RESET}"
  printf '%s%s%s\n' "${C_DIM}" "  Production-ready Nginx traffic analytics (Bash + plugins)" "${C_RESET}"
  ntm_hr "="
  printf 'Terminal width: %s | Log: %s\n' "$w" "$(ntm_effective_log 2>/dev/null || echo "$NTM_TRAFFIC_LOG")"
}

ntm_render_menu() {
  ntm_run_hooks before_menu
  ntm_print_banner
  printf '\n%sMain Menu%s\n' "${C_BOLD}" "${C_RESET}"
  ntm_hr "-"
  local n=0 line id label
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    n=$((n + 1))
    id="$(printf '%s' "$line" | cut -d'|' -f2)"
    label="$(printf '%s' "$line" | cut -d'|' -f3)"
    if printf '%s' "$label" | grep -Eq '^[0-9]+\)'; then
      printf '  %s%s%s\n' "${C_GREEN}" "$label" "${C_RESET}"
    else
      printf '  %s%2d)%s %s\n' "${C_GREEN}" "$n" "${C_RESET}" "$label"
    fi
  done <<EOF
$(ntm_menu_sorted_lines | sort -t'|' -k1,1n)
EOF
  printf '  %s%2d)%s Exit\n' "${C_YELLOW}" 0 "${C_RESET}"
  ntm_hr "-"
}

ntm_menu_loop() {
  local choice func id count
  while true; do
    ntm_render_menu
    count="$(ntm_menu_sorted_lines | sort -t'|' -k1,1n | grep -c . || true)"
    printf '%sSelect option [0-%s]:%s ' "${C_BOLD}" "$count" "${C_RESET}"
    # shellcheck disable=SC2162
    read -r choice || choice=0
    case "$choice" in
      0|q|Q|exit|quit)
        ntm_info "Goodbye."
        exit 0
        ;;
      ''|*[!0-9]*)
        ntm_warn "Invalid selection"
        ntm_pause
        continue
        ;;
    esac
    if [ "$choice" -lt 1 ] || [ "$choice" -gt "$count" ]; then
      ntm_warn "Out of range"
      ntm_pause
      continue
    fi
    id="$(ntm_menu_get_id "$choice")"
    func="$(ntm_menu_get_func "$choice")"
    ntm_run_hooks after_menu_select "$id" "$choice"
    printf '\n'
    if [ -n "$func" ] && declare -F "$func" >/dev/null 2>&1; then
      "$func" || ntm_warn "Plugin exited with an error"
    else
      ntm_error "No handler for menu item $choice"
    fi
    ntm_pause
  done
}

ntm_usage() {
  cat <<EOF
${NTM_APP_NAME} v${NTM_APP_VERSION}

Usage:
  ./traffic-monitor.sh                     Interactive menu
  ./traffic-monitor.sh --report <period>   Full report (today|yesterday|24h|7d|30d|all)
  ./traffic-monitor.sh --today             Shortcut report
  ./traffic-monitor.sh --export [html|txt] Export report (--period, --out)
  ./traffic-monitor.sh --live              Live monitor
  ./traffic-monitor.sh --isp-report        ISP/ASN breakdown
  ./traffic-monitor.sh --plugins list|enable <id>|disable <id>
  ./traffic-monitor.sh --doctor            Environment & install checks
  ./traffic-monitor.sh --sample            Force sample log (demo)
  ./traffic-monitor.sh -h|--help           This help

Periods: today, yesterday, 24h, 7d, 30d, all
EOF
}

# Pre-scan modifiers so order does not matter
ntm_cli_prescan() {
  local i=0
  local -a args=("$@")
  while [ "$i" -lt "${#args[@]}" ]; do
    case "${args[$i]}" in
      --sample) export NTM_FORCE_SAMPLE=1 ;;
      --period)
        i=$((i + 1))
        NTM_CLI_PERIOD="${args[$i]:-today}"
        ;;
      --out|--output)
        i=$((i + 1))
        NTM_CLI_OUT="${args[$i]:-}"
        ;;
      --format)
        i=$((i + 1))
        NTM_CLI_FORMAT="${args[$i]:-html}"
        ;;
    esac
    i=$((i + 1))
  done
  export NTM_CLI_PERIOD NTM_CLI_OUT NTM_CLI_FORMAT
}

ntm_handle_cli() {
  ntm_cli_prescan "$@"
  local -a args=("$@")
  local i=0
  local ran=0

  while [ "$i" -lt "${#args[@]}" ]; do
    local a="${args[$i]}"
    case "$a" in
      -h|--help)
        ntm_usage
        exit 0
        ;;
      --sample|--period|--out|--output|--format)
        # consumed in prescan; skip values
        case "$a" in
          --period|--out|--output|--format) i=$((i + 1)) ;;
        esac
        ;;
      --doctor)
        ntm_doctor
        ran=1
        ;;
      --plugins)
        i=$((i + 1))
        local sub="${args[$i]:-list}"
        case "$sub" in
          list) ntm_plugins_list ;;
          enable)
            i=$((i + 1))
            ntm_set_plugin_enabled "${args[$i]:-}" 1
            ntm_ok "Enabled ${args[$i]:-}"
            ;;
          disable)
            i=$((i + 1))
            ntm_set_plugin_enabled "${args[$i]:-}" 0
            ntm_ok "Disabled ${args[$i]:-}"
            ;;
          *)
            ntm_error "Unknown --plugins subcommand: $sub"
            exit 1
            ;;
        esac
        ran=1
        ;;
      --report)
        i=$((i + 1))
        NTM_CLI_PERIOD="${args[$i]:-$NTM_CLI_PERIOD}"
        export NTM_CLI_PERIOD
        ntm_run_report "$NTM_CLI_PERIOD"
        ran=1
        ;;
      --export)
        # optional format token
        if [ $((i + 1)) -lt "${#args[@]}" ]; then
          case "${args[$((i + 1))]}" in
            html|HTML|txt|TXT)
              i=$((i + 1))
              NTM_CLI_FORMAT="${args[$i]}"
              export NTM_CLI_FORMAT
              ;;
          esac
        fi
        if declare -F ntm_plug_export_run >/dev/null 2>&1; then
          ntm_plug_export_run
        else
          ntm_error "export plugin not loaded"
          exit 1
        fi
        ran=1
        ;;
      *)
        local fn
        if fn="$(ntm_cli_find_func "$a")"; then
          "$fn" "$@"
          ran=1
        else
          ntm_error "Unknown option: $a (try --help)"
          exit 1
        fi
        ;;
    esac
    i=$((i + 1))
  done

  [ "$ran" -eq 1 ]
}

if [ "$#" -gt 0 ]; then
  if ntm_handle_cli "$@"; then
    exit 0
  fi
fi

ntm_menu_loop
