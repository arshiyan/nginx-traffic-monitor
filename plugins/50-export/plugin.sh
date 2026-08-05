#!/usr/bin/env bash
# Export plugin — TXT and pure HTML/CSS dashboard

plugin_init() {
  ntm_register_hook after_report ntm_export_cache_period || true
}

# Remember last report period for hooks
ntm_export_cache_period() {
  NTM_LAST_REPORT_PERIOD="${1:-today}"
  export NTM_LAST_REPORT_PERIOD
}

ntm_export_ask_format() {
  if [ -n "${NTM_CLI_FORMAT:-}" ] && [ "${1:-}" = "cli" ]; then
    printf '%s' "$NTM_CLI_FORMAT"
    return 0
  fi
  printf 'Export format [1=TXT, 2=HTML] (default 2): '
  # shellcheck disable=SC2162
  read -r ans || true
  case "$ans" in
    1|txt|TXT) printf 'txt' ;;
    *) printf 'html' ;;
  esac
}

ntm_export_ask_period() {
  if [ -n "${NTM_CLI_PERIOD:-}" ]; then
    printf '%s' "$NTM_CLI_PERIOD"
    return 0
  fi
  printf 'Period [today|yesterday|24h|7d|30d|all] (default today): '
  # shellcheck disable=SC2162
  read -r ans || true
  [ -z "$ans" ] && ans="today"
  printf '%s' "$ans"
}

ntm_export_txt() {
  local period="$1" out="$2"
  {
    echo "Nginx Traffic Monitor — Export"
    echo "Generated: $(date)"
    echo "Period: $period"
    echo "========================================"
    ntm_run_report "$period"
  } >"$out"
  ntm_ok "TXT report written: $out"
}

ntm_export_html() {
  local period="$1" out="$2"
  local logfile summary urls ips statuses hosts
  logfile="$(ntm_effective_log)"
  summary="$(ntm_report_summary "$period" "$logfile" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')"
  urls="$(ntm_top_field "$period" url "$logfile" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')"
  ips="$(ntm_top_field "$period" ip "$logfile" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')"
  statuses="$(ntm_top_field "$period" status "$logfile" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')"
  hosts="$(ntm_top_field "$period" host "$logfile" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')"

  # Build CSS bar chart rows from status counts
  local bars=""
  local max=1 line cnt label pct
  max="$(printf '%s\n' "$statuses" | awk '{if($1+0>m)m=$1+0} END{print m+0}')"
  [ "$max" -lt 1 ] && max=1
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    cnt="$(printf '%s' "$line" | awk '{print $1+0}')"
    label="$(printf '%s' "$line" | awk '{print $NF}')"
    pct=$((cnt * 100 / max))
    bars="${bars}<div class=\"bar-row\"><span class=\"bar-label\">${label}</span><div class=\"bar\" style=\"width:${pct}%\"></div><span class=\"bar-val\">${cnt}</span></div>"$'\n'
  done <<EOF
$statuses
EOF

  local isp_section=""
  if declare -F ntm_plug_isp_asn_html_snippet >/dev/null 2>&1; then
    isp_section="$(ntm_plug_isp_asn_html_snippet "$period" 2>/dev/null || true)"
  fi

  ntm_run_hooks before_export "$period" "$out"

  cat >"$out" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>Nginx Traffic Monitor — ${period}</title>
<style>
:root {
  --bg: #0f1419;
  --panel: #1a2332;
  --text: #e7ecf3;
  --muted: #8b9bb4;
  --accent: #3d9cf0;
  --ok: #3ecf8e;
  --warn: #f0b429;
  --border: #2a3548;
}
* { box-sizing: border-box; }
body {
  margin: 0; font-family: "Segoe UI", "Helvetica Neue", Arial, sans-serif;
  background: radial-gradient(1200px 600px at 10% -10%, #1b2a44 0%, var(--bg) 55%);
  color: var(--text); line-height: 1.5;
}
header {
  padding: 2rem 2rem 1rem; border-bottom: 1px solid var(--border);
}
header h1 { margin: 0 0 .25rem; font-size: 1.6rem; letter-spacing: .02em; }
header p { margin: 0; color: var(--muted); }
main { padding: 1.5rem 2rem 3rem; max-width: 1100px; margin: 0 auto; }
.grid { display: grid; gap: 1rem; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); }
.card {
  background: var(--panel); border: 1px solid var(--border); border-radius: 12px;
  padding: 1rem 1.1rem;
}
.card h2 { margin: 0 0 .75rem; font-size: 1rem; color: var(--accent); text-transform: uppercase; letter-spacing: .08em; }
pre {
  margin: 0; white-space: pre-wrap; word-break: break-word;
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: .85rem; color: var(--text);
}
.bar-row { display: flex; align-items: center; gap: .6rem; margin: .35rem 0; }
.bar-label { width: 3.2rem; color: var(--muted); font-size: .85rem; }
.bar {
  height: 10px; background: linear-gradient(90deg, var(--accent), var(--ok));
  border-radius: 999px; min-width: 4px;
}
.bar-val { color: var(--muted); font-size: .8rem; }
footer { padding: 1rem 2rem 2rem; color: var(--muted); font-size: .8rem; }
</style>
</head>
<body>
<header>
  <h1>Nginx Traffic Monitor</h1>
  <p>Period: <strong>${period}</strong> · Generated $(date) · Pure HTML/CSS (no JavaScript)</p>
</header>
<main>
  <div class="grid">
    <section class="card"><h2>Summary</h2><pre>${summary}</pre></section>
    <section class="card"><h2>Status Codes</h2>${bars}<pre>${statuses}</pre></section>
  </div>
  <div class="grid" style="margin-top:1rem">
    <section class="card"><h2>Top URLs</h2><pre>${urls}</pre></section>
    <section class="card"><h2>Top IPs</h2><pre>${ips}</pre></section>
  </div>
  <div class="grid" style="margin-top:1rem">
    <section class="card"><h2>Top Hosts</h2><pre>${hosts}</pre></section>
    <section class="card"><h2>ISP / ASN</h2>${isp_section:-<pre>ISP plugin inactive or no data.</pre>}</section>
  </div>
</main>
<footer>Nginx Traffic Monitor — enterprise Bash analytics · plugin architecture</footer>
</body>
</html>
EOF

  ntm_run_hooks after_export "$period" "$out"
  ntm_ok "HTML dashboard written: $out"
}

plugin_run() {
  local period format out dir
  local interactive=0
  [ -t 0 ] && [ -z "${NTM_CLI_OUT:-}" ] && interactive=1

  if [ "$interactive" -eq 1 ]; then
    period="$(ntm_export_ask_period)"
    format="$(ntm_export_ask_format)"
  else
    period="${NTM_CLI_PERIOD:-today}"
    format="${NTM_CLI_FORMAT:-html}"
  fi

  dir="${NTM_EXPORT_DIR}"
  mkdir -p "$dir" 2>/dev/null || dir="/tmp"
  if [ -n "${NTM_CLI_OUT:-}" ]; then
    out="$NTM_CLI_OUT"
  else
    out="${dir}/report-${period}-$(ntm_timestamp).${format}"
  fi

  case "$format" in
    html|HTML) ntm_export_html "$period" "$out" ;;
    *) ntm_export_txt "$period" "$out" ;;
  esac
}

plugin_help() {
  echo "Export a TXT or HTML/CSS dashboard report."
}
