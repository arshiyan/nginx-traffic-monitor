#!/usr/bin/env bash
# ISP / ASN plugin — Irancell, Hamrah-e Avval (MCI), Other

ISP_PLUGIN_DIR=""

plugin_init() {
  ISP_PLUGIN_DIR="${NTM_CURRENT_PLUGIN_DIR}"
  # Expose HTML snippet helper with stable name for export plugin
  # (loader also wraps as ntm_plug_isp_asn_run)
}

_isp_data_dir() {
  if [ -n "${ISP_PLUGIN_DIR:-}" ]; then
    printf '%s/data' "$ISP_PLUGIN_DIR"
  else
    printf '%s/plugins/43-isp-asn/data' "$NTM_ROOT"
  fi
}

_isp_awk() {
  if [ -n "${ISP_PLUGIN_DIR:-}" ]; then
    printf '%s/asn_match.awk' "$ISP_PLUGIN_DIR"
  else
    printf '%s/plugins/43-isp-asn/asn_match.awk' "$NTM_ROOT"
  fi
}

_isp_label() {
  case "$1" in
    irancell) printf 'Irancell (ایرانسل)' ;;
    mci) printf 'Hamrah-e Avval / MCI (همراه‌اول)' ;;
    other) printf 'Other ISPs (سایر)' ;;
    *) printf '%s' "$1" ;;
  esac
}

# Run classification; prints machine lines to stdout
_isp_classify() {
  local period="$1"
  local data awkf
  data="$(_isp_data_dir)"
  awkf="$(_isp_awk)"
  ntm_filter_log "$period" | awk -f "$awkf" \
    -v irancell_file="${data}/irancell.cidr" \
    -v mci_file="${data}/mci.cidr" \
    -v other_file="${data}/other.cidr"
}

_isp_render_report() {
  local period="$1"
  local raw total_req total_byt
  raw="$(_isp_classify "$period")"

  total_req="$(printf '%s\n' "$raw" | awk -F'\t' '$1=="TOTAL"{print $2; exit}')"
  total_byt="$(printf '%s\n' "$raw" | awk -F'\t' '$1=="TOTAL"{print $3; exit}')"
  : "${total_req:=0}"
  : "${total_byt:=0}"

  ntm_title "ISP Traffic (ASN) — ${period}"
  printf 'Flat-file ASN DB: %s\n' "$(_isp_data_dir)"
  printf 'Total requests: %s | Total traffic: %s\n\n' "$total_req" "$(ntm_human_bytes "$total_byt")"

  if [ "$total_req" = "0" ]; then
    ntm_warn "No requests in this period."
    return 0
  fi

  printf '%-36s %10s %12s %8s\n' "ISP" "REQUESTS" "TRAFFIC" "SHARE"
  ntm_hr "-"

  local g req byt pct
  for g in irancell mci other; do
    req="$(printf '%s\n' "$raw" | awk -F'\t' -v g="$g" '$1=="GROUP" && $2==g {print $3; found=1} END{if(!found) print 0}')"
    byt="$(printf '%s\n' "$raw" | awk -F'\t' -v g="$g" '$1=="GROUP" && $2==g {print $4; found=1} END{if(!found) print 0}')"
    if [ "$total_req" -gt 0 ]; then
      pct="$(awk -v a="$req" -v b="$total_req" 'BEGIN{printf "%.1f", (a*100)/b}')"
    else
      pct="0.0"
    fi
    printf '%-36s %10s %12s %7s%%\n' "$(_isp_label "$g")" "$req" "$(ntm_human_bytes "$byt")" "$pct"
  done

  printf '\n'
  for g in irancell mci other; do
    printf '%s=== Top IPs — %s ===%s\n' "${C_BOLD}" "$(_isp_label "$g")" "${C_RESET}"
    printf '%s\n' "$raw" | awk -F'\t' -v g="$g" '$1=="IP" && $2==g {printf "%d\t%d\t%s\n",$4,$5,$3}' \
      | sort -t"$(printf '\t')" -k1,1nr | head -n 10 | awk -F'\t' '
        function human(b, u, i, x) {
          split("B KB MB GB TB", u, " ")
          x=b+0; i=1
          while (x>=1024 && i<5) { x/=1024; i++ }
          if (i==1) return sprintf("%d %s", x, u[i])
          return sprintf("%.2f %s", x, u[i])
        }
        { printf "  %6s  %10s  %s\n", $1, human($2), $3 }
      '
    printf '\n'
  done

  ntm_info "Note: CDN/proxy IPs may not reflect the end-user ISP. Keep CIDR files updated."
}

# HTML snippet for export dashboard
ntm_plug_isp_asn_html_snippet() {
  local period="${1:-today}"
  local raw total_req g req byt pct max
  raw="$(_isp_classify "$period")"
  total_req="$(printf '%s\n' "$raw" | awk -F'\t' '$1=="TOTAL"{print $2; exit}')"
  : "${total_req:=0}"
  max=1
  [ "$total_req" -gt 0 ] && max="$total_req"

  printf '<pre>'
  for g in irancell mci other; do
    req="$(printf '%s\n' "$raw" | awk -F'\t' -v g="$g" '$1=="GROUP" && $2==g {print $3; f=1} END{if(!f) print 0}')"
    byt="$(printf '%s\n' "$raw" | awk -F'\t' -v g="$g" '$1=="GROUP" && $2==g {print $4; f=1} END{if(!f) print 0}')"
    pct="$(awk -v a="$req" -v b="$max" 'BEGIN{printf "%.1f", (a*100)/(b==0?1:b)}')"
    printf '%s: %s req · %s · %s%%\n' "$(_isp_label "$g")" "$req" "$(ntm_human_bytes "$byt")" "$pct"
  done
  printf '</pre>'
  for g in irancell mci other; do
    req="$(printf '%s\n' "$raw" | awk -F'\t' -v g="$g" '$1=="GROUP" && $2==g {print $3; f=1} END{if(!f) print 0}')"
    pct=$((req * 100 / max))
    [ "$pct" -gt 100 ] && pct=100
    printf '<div class="bar-row"><span class="bar-label">%s</span><div class="bar" style="width:%s%%"></div><span class="bar-val">%s</span></div>\n' \
      "$g" "$pct" "$req"
  done
}

_isp_update_db() {
  local data
  data="$(_isp_data_dir)"
  ntm_title "Update ASN / CIDR database"
  ntm_info "Database directory: $data"
  ntm_info "Edit irancell.cidr / mci.cidr / asn_map.conf manually, or fetch with curl if available."

  if command -v curl >/dev/null 2>&1; then
    ntm_info "curl detected. Optional public sources (examples):"
    printf '  # Example (manual review recommended):\n'
    printf '  # curl -fsSL https://raw.githubusercontent.com/sapics/ip-location-db/... -o /tmp/asn.csv\n'
    ntm_warn "Automatic full ASN download is not forced — verify licensing and accuracy."
    ntm_info "After downloading prefixes for AS44244 / AS197207, append CIDRs to the data files."
  else
    ntm_warn "curl not found — update CIDR files manually:"
    printf '  %s/irancell.cidr\n' "$data"
    printf '  %s/mci.cidr\n' "$data"
    printf '  %s/asn_map.conf\n' "$data"
  fi
  ntm_ok "Seed database is ready for use without network access."
}

plugin_run() {
  # Detect --isp-update-db via first matching argv in global $@
  local a
  for a in "$@"; do
    if [ "$a" = "--isp-update-db" ]; then
      _isp_update_db
      return 0
    fi
  done

  local period="${NTM_CLI_PERIOD:-}"
  if [ -z "$period" ] && [ -t 0 ]; then
    printf 'Period [today|yesterday|24h|7d|30d|all] (default today): '
    # shellcheck disable=SC2162
    read -r period || true
  fi
  : "${period:=today}"

  local out="${NTM_CLI_OUT:-}"
  if [ -n "$out" ]; then
    _isp_render_report "$period" | tee "$out"
    ntm_ok "ISP report saved: $out"
  else
    _isp_render_report "$period"
  fi
}

plugin_help() {
  echo "Break down traffic by Irancell, MCI, and other ISPs using flat-file CIDR/ASN data."
}
