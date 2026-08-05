#!/usr/bin/env bash
# parse.sh — date filtering and shared report engine (portable awk + sort)

[ -n "${NTM_PARSE_LOADED:-}" ] && return 0
NTM_PARSE_LOADED=1

# Compute ISO8601 window start/end for a period keyword
# Prints: START|END  (lexicographically comparable with time_iso8601)
ntm_period_window() {
  local period="${1:-today}"
  local start end now
  now="$(date '+%Y-%m-%dT%H:%M:%S')"

  case "$period" in
    today)
      start="$(date '+%Y-%m-%dT00:00:00')"
      end="$(date '+%Y-%m-%dT23:59:59')"
      ;;
    yesterday)
      if date -d 'yesterday' '+%Y-%m-%d' >/dev/null 2>&1; then
        start="$(date -d 'yesterday' '+%Y-%m-%dT00:00:00')"
        end="$(date -d 'yesterday' '+%Y-%m-%dT23:59:59')"
      else
        start="$(date -v-1d '+%Y-%m-%dT00:00:00' 2>/dev/null || date '+%Y-%m-%dT00:00:00')"
        end="$(date -v-1d '+%Y-%m-%dT23:59:59' 2>/dev/null || date '+%Y-%m-%dT23:59:59')"
      fi
      ;;
    24h|last24h|last_24h)
      if date -d '24 hours ago' '+%Y-%m-%dT%H:%M:%S' >/dev/null 2>&1; then
        start="$(date -d '24 hours ago' '+%Y-%m-%dT%H:%M:%S')"
      else
        start="$(date -v-24H '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || date '+%Y-%m-%dT00:00:00')"
      fi
      end="$now"
      ;;
    7d|last7d|last_7d)
      if date -d '7 days ago' '+%Y-%m-%dT%H:%M:%S' >/dev/null 2>&1; then
        start="$(date -d '7 days ago' '+%Y-%m-%dT%H:%M:%S')"
      else
        start="$(date -v-7d '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || date '+%Y-%m-%dT00:00:00')"
      fi
      end="$now"
      ;;
    30d|last30d|last_30d)
      if date -d '30 days ago' '+%Y-%m-%dT%H:%M:%S' >/dev/null 2>&1; then
        start="$(date -d '30 days ago' '+%Y-%m-%dT%H:%M:%S')"
      else
        start="$(date -v-30d '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || date '+%Y-%m-%dT00:00:00')"
      fi
      end="$now"
      ;;
    all|*)
      start="1970-01-01T00:00:00"
      end="9999-12-31T23:59:59"
      ;;
  esac
  printf '%s|%s' "$start" "$end"
}

# Stream filtered log lines for period to stdout
ntm_filter_log() {
  local period="${1:-today}"
  local logfile="${2:-}"
  local window start end
  [ -z "$logfile" ] && logfile="$(ntm_effective_log)"
  if [ ! -r "$logfile" ]; then
    ntm_error "Cannot read log: $logfile"
    return 1
  fi
  window="$(ntm_period_window "$period")"
  start="${window%%|*}"
  end="${window##*|}"

  awk -v start="$start" -v end="$end" '
    {
      ts = $1
      gsub(/[Zz]$/, "", ts)
      sub(/[+-][0-9][0-9]:[0-9][0-9]$/, "", ts)
      if (ts >= start && ts <= end) print
    }
  ' "$logfile"
}

# Summary metrics (requests, bytes, avg, largest)
ntm_report_summary() {
  local period="$1"
  local logfile="$2"
  ntm_filter_log "$period" "$logfile" | awk '
    function human(b,    u, i, x) {
      split("B KB MB GB TB PB", u, " ")
      x = b + 0; i = 1
      while (x >= 1024 && i < 6) { x /= 1024; i++ }
      if (i == 1) return sprintf("%d %s", x, u[i])
      return sprintf("%.2f %s", x, u[i])
    }
    {
      bytes = $NF + 0
      uri = ""
      if (match($0, /"[^"]*"/)) uri = substr($0, RSTART+1, RLENGTH-2)
      ip = $2
      total_req++
      total_bytes += bytes
      if (bytes >= max_bytes) { max_bytes = bytes; max_url = uri; max_ip = ip }
    }
    END {
      if (total_req == 0) {
        print "No requests found in this period."
        exit 0
      }
      avg = total_bytes / total_req
      printf "Total Requests:        %d\n", total_req
      printf "Total Traffic:         %s (%d bytes)\n", human(total_bytes), total_bytes
      printf "Average Response Size: %s\n", human(avg)
      printf "Largest Request:       %s (%s) from %s\n", max_url, human(max_bytes), max_ip
    }
  '
}

# Top N helper: mode = url|ip|status|host|ext
ntm_top_field() {
  local period="$1"
  local mode="$2"
  local logfile="${3:-}"
  local topn="${NTM_TOP_N:-20}"
  [ -z "$logfile" ] && logfile="$(ntm_effective_log)"

  ntm_filter_log "$period" "$logfile" | awk -v mode="$mode" '
    {
      ip=$2; host=$3; status=$4; bytes=$NF+0
      uri=""
      if (match($0, /"[^"]*"/)) uri = substr($0, RSTART+1, RLENGTH-2)
      if (mode=="url") key=uri
      else if (mode=="ip") key=ip
      else if (mode=="status") key=status
      else if (mode=="host") key=host
      else if (mode=="ext") {
        key="(none)"
        path = uri
        sub(/\?.*/, "", path)
        if (match(path, /\.([A-Za-z0-9]+)$/)) key = substr(path, RSTART+1, RLENGTH-1)
        else if (path == "/" || path == "") key = "(root)"
      } else key=uri
      count[key]++
      bsum[key] += bytes
    }
    END {
      for (k in count) printf "%d\t%d\t%s\n", count[k], bsum[k], k
    }
  ' | sort -t"$(printf '\t')" -k1,1nr | head -n "$topn" | awk -F'\t' '
    function human(b,    u, i, x) {
      split("B KB MB GB TB PB", u, " ")
      x = b + 0; i = 1
      while (x >= 1024 && i < 6) { x /= 1024; i++ }
      if (i == 1) return sprintf("%d %s", x, u[i])
      return sprintf("%.2f %s", x, u[i])
    }
    {
      printf "%6s  %10s  %s\n", $1, human($2), $3
      for (i=4; i<=NF; i++) printf " %s", $i
      if (NF>3) printf "\n"
    }
  '
}

# Full report for a period
ntm_run_report() {
  local period="${1:-today}"
  local logfile
  logfile="$(ntm_effective_log)"

  ntm_run_hooks before_report "$period" "$logfile"

  if [ ! -r "$logfile" ]; then
    ntm_error "Log not readable: $logfile"
    return 1
  fi

  local window start end
  window="$(ntm_period_window "$period")"
  start="${window%%|*}"
  end="${window##*|}"

  ntm_title "Traffic Report — ${period}"
  printf 'Log: %s\nWindow: %s → %s\n\n' "$logfile" "$start" "$end"

  ntm_report_summary "$period" "$logfile"
  printf '\n=== Top URLs ===\n'
  ntm_top_field "$period" url "$logfile"
  printf '\n=== Top Client IPs ===\n'
  ntm_top_field "$period" ip "$logfile"
  printf '\n=== Top Status Codes ===\n'
  ntm_top_field "$period" status "$logfile"
  printf '\n=== Top Hosts ===\n'
  ntm_top_field "$period" host "$logfile"
  printf '\n=== Top File Extensions ===\n'
  ntm_top_field "$period" ext "$logfile"

  ntm_run_hooks after_report "$period" "$logfile"
}

ntm_log_size_report() {
  local logfile
  logfile="$(ntm_effective_log)"
  ntm_title "Current Log Size"
  if [ ! -e "$logfile" ]; then
    ntm_error "Log does not exist: $logfile"
    return 1
  fi
  local bytes lines
  bytes="$(stat -c '%s' "$logfile" 2>/dev/null || stat -f '%z' "$logfile" 2>/dev/null || wc -c <"$logfile")"
  lines="$(wc -l <"$logfile" | tr -d ' ')"
  printf 'Path:   %s\n' "$logfile"
  printf 'Size:   %s (%s bytes)\n' "$(ntm_human_bytes "$bytes")" "$bytes"
  printf 'Lines:  %s\n' "$lines"
}

# Doctor / deep verify
ntm_doctor() {
  ntm_title "Doctor — environment check"
  ntm_info "App: ${NTM_APP_NAME} ${NTM_APP_VERSION}"
  ntm_info "Root: ${NTM_ROOT}"
  local tool
  for tool in bash awk grep sed find cut sort uniq stat tail wc date; do
    if command -v "$tool" >/dev/null 2>&1; then
      ntm_ok "found: $tool"
    else
      ntm_error "missing: $tool"
    fi
  done
  ntm_verify_installation || true
  ntm_plugins_list
}
