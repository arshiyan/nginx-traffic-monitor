#!/usr/bin/env bash
# Live monitor — refresh every second

plugin_init() { :; }

plugin_run() {
  local logfile prev_size prev_lines size lines delta_lines delta_bytes
  local last_line last_ip last_uri rps bw
  logfile="$(ntm_effective_log)"

  if [ ! -r "$logfile" ]; then
    ntm_error "Cannot read log: $logfile"
    return 1
  fi

  ntm_title "Live Monitor"
  ntm_info "Watching $logfile — Ctrl+C to stop"
  printf '\n'

  prev_size="$(stat -c '%s' "$logfile" 2>/dev/null || stat -f '%z' "$logfile")"
  prev_lines="$(wc -l <"$logfile" | tr -d ' ')"

  trap 'printf "\n"; ntm_info "Live monitor stopped"; trap - INT; return 0' INT

  while true; do
    size="$(stat -c '%s' "$logfile" 2>/dev/null || stat -f '%z' "$logfile")"
    lines="$(wc -l <"$logfile" | tr -d ' ')"
    delta_lines=$((lines - prev_lines))
    delta_bytes=$((size - prev_size))
    [ "$delta_lines" -lt 0 ] && delta_lines=0
    [ "$delta_bytes" -lt 0 ] && delta_bytes=0
    rps="$delta_lines"
    bw="$delta_bytes"
    last_line="$(tail -n1 "$logfile" 2>/dev/null || true)"
    last_ip="$(printf '%s' "$last_line" | awk '{print $2}')"
    last_uri=""
    if printf '%s' "$last_line" | grep -q '"'; then
      last_uri="$(printf '%s' "$last_line" | sed -n 's/.*"\([^"]*\)".*/\1/p')"
    fi

    # Clear screen if interactive TTY
    if [ -t 1 ]; then
      printf '\033[H\033[2J'
    fi
    ntm_title "Live Monitor"
    printf 'Log: %s\n' "$logfile"
    printf 'Time: %s\n\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    printf '%sCurrent requests/s:%s  %s\n' "${C_BOLD}" "${C_RESET}" "$rps"
    printf '%sEstimated bandwidth:%s %s/s (%s bytes)\n' "${C_BOLD}" "${C_RESET}" "$(ntm_human_bytes "$bw")" "$bw"
    printf '%sLog size:%s            %s (Δ %s)\n' "${C_BOLD}" "${C_RESET}" "$(ntm_human_bytes "$size")" "$(ntm_human_bytes "$delta_bytes")"
    printf '%sLog lines:%s           %s\n' "${C_BOLD}" "${C_RESET}" "$lines"
    printf '%sLast client:%s         %s\n' "${C_BOLD}" "${C_RESET}" "${last_ip:-n/a}"
    printf '%sLast request:%s        %s\n' "${C_BOLD}" "${C_RESET}" "${last_uri:-n/a}"
    printf '\n%s%s%s\n' "${C_DIM}" "$last_line" "${C_RESET}"

    ntm_run_hooks on_live_tick "$rps" "$bw" "$last_ip" "$last_uri"

    prev_size="$size"
    prev_lines="$lines"
    sleep 1
  done
}

plugin_help() {
  echo "Display live requests/s, bandwidth estimate, last client/request, and log growth."
}
