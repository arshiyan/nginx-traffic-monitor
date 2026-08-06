#!/usr/bin/env bash
# nginx.sh — detect nginx, backup/restore conf, install traffic logging, validate, reload

[ -n "${NTM_NGINX_LOADED:-}" ] && return 0
NTM_NGINX_LOADED=1

ntm_detect_nginx_bin() {
  if [ -n "${NTM_NGINX_BIN:-}" ] && [ -x "$NTM_NGINX_BIN" ]; then
    printf '%s' "$NTM_NGINX_BIN"
    return 0
  fi

  # Prefer the running master process binary (aaPanel/BT, custom builds)
  local master
  master="$(ps -eo args= 2>/dev/null | grep -E '^nginx: master process' | head -n1 | sed -E 's/^nginx: master process[[:space:]]+//; s/[[:space:]]-c.*//; s/[[:space:]]+$//' || true)"
  # Also match "/path/nginx -c ..." forms from full cmdline listings
  if [ -z "$master" ] || [ ! -x "$master" ]; then
    master="$(ps -eo args= 2>/dev/null | grep -E '/nginx[[:space:]]+-c|/sbin/nginx' | grep -v panel/webserver | grep -v grep | head -n1 | awk '{print $1}' || true)"
  fi
  if [ -n "$master" ] && [ -x "$master" ]; then
    printf '%s' "$master"
    return 0
  fi

  # aaPanel / BT Panel
  if [ -x /www/server/nginx/sbin/nginx ]; then
    printf '%s' /www/server/nginx/sbin/nginx
    return 0
  fi

  if command -v nginx >/dev/null 2>&1; then
    command -v nginx
    return 0
  fi
  for p in /usr/sbin/nginx /usr/bin/nginx /sbin/nginx; do
    if [ -x "$p" ]; then
      printf '%s' "$p"
      return 0
    fi
  done
  return 1
}

# Score a candidate nginx.conf (higher = better). Used by limited find.
ntm_nginx_conf_score() {
  local p="$1"
  local score=0
  local dir
  dir="$(dirname "$p")"
  case "$p" in
    *nginx*) score=$((score + 10)) ;;
  esac
  [ -f "${dir}/mime.types" ] && score=$((score + 5))
  [ -d "${dir}/conf.d" ] && score=$((score + 3))
  [ -d "${dir}/sites-enabled" ] && score=$((score + 3))
  [ -d "${dir}/http.d" ] && score=$((score + 2))
  # Prefer real main configs over samples/templates/backups
  case "$p" in
    *sample*|*example*|*backup*|*bak*|*template*) score=$((score - 20)) ;;
  esac
  printf '%s' "$score"
}

ntm_detect_nginx_conf() {
  if [ -n "${NTM_NGINX_CONF:-}" ] && [ -f "$NTM_NGINX_CONF" ]; then
    printf '%s' "$NTM_NGINX_CONF"
    return 0
  fi

  local bin conf prefix p best best_score score
  bin="$(ntm_detect_nginx_bin 2>/dev/null || true)"

  # 1) --conf-path= from nginx -V
  if [ -n "$bin" ]; then
    conf="$("$bin" -V 2>&1 | tr ' ' '\n' | grep -E '^--conf-path=' | head -n1 | cut -d= -f2- || true)"
    if [ -n "$conf" ] && [ -f "$conf" ]; then
      printf '%s' "$conf"
      return 0
    fi

    # 2) path from nginx -t ("configuration file /path/nginx.conf ...")
    conf="$("$bin" -t 2>&1 | grep -Eo 'configuration file [^[:space:]]+' | head -n1 | awk '{print $3}' || true)"
    if [ -n "$conf" ] && [ -f "$conf" ]; then
      printf '%s' "$conf"
      return 0
    fi

    # 3) --prefix= → {prefix}/conf/nginx.conf and {prefix}/nginx.conf
    prefix="$("$bin" -V 2>&1 | tr ' ' '\n' | grep -E '^--prefix=' | head -n1 | cut -d= -f2- || true)"
    if [ -n "$prefix" ]; then
      for p in "${prefix}/conf/nginx.conf" "${prefix}/nginx.conf"; do
        if [ -f "$p" ]; then
          printf '%s' "$p"
          return 0
        fi
      done
    fi
  fi

  # 4) Known common paths (Debian/Ubuntu, source builds, OpenResty, aaPanel/BT)
  # Prefer aaPanel path when present (before generic /etc/nginx)
  for p in \
    /www/server/nginx/conf/nginx.conf \
    /etc/nginx/nginx.conf \
    /etc/nginx/conf/nginx.conf \
    /usr/local/nginx/conf/nginx.conf \
    /usr/local/etc/nginx/nginx.conf \
    /opt/nginx/conf/nginx.conf \
    /usr/local/openresty/nginx/conf/nginx.conf \
    /opt/openresty/nginx/conf/nginx.conf
  do
    if [ -f "$p" ]; then
      printf '%s' "$p"
      return 0
    fi
  done

  # 5) Limited find under common roots (not entire filesystem)
  best=""
  best_score=-999
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    [ -f "$p" ] || continue
    score="$(ntm_nginx_conf_score "$p")"
    if [ "$score" -gt "$best_score" ]; then
      best_score="$score"
      best="$p"
    fi
  done <<EOF
$(find /etc /usr/local /opt /www -name nginx.conf -type f 2>/dev/null | head -n 20)
EOF

  if [ -n "$best" ] && [ -f "$best" ] && [ "$best_score" -ge 0 ]; then
    printf '%s' "$best"
    return 0
  fi

  return 1
}

ntm_nginx_worker_user() {
  local conf user
  conf="$(ntm_detect_nginx_conf 2>/dev/null || true)"
  user="www-data"
  if [ -n "$conf" ] && [ -f "$conf" ]; then
    user="$(grep -E '^\s*user\s+' "$conf" | head -n1 | awk '{print $2}' | tr -d ';' || true)"
    [ -z "$user" ] && user="www-data"
  fi
  printf '%s' "$user"
}

ntm_backup_nginx_conf() {
  local conf dest ts
  conf="$(ntm_detect_nginx_conf)" || return 1
  mkdir -p "$NTM_BACKUP_DIR"
  ts="$(ntm_timestamp)"
  dest="${NTM_BACKUP_DIR}/nginx.conf.${ts}.bak"
  cp -a "$conf" "$dest"
  # Keep a pointer to the latest backup for easy rollback
  printf '%s\n' "$dest" >"${NTM_BACKUP_DIR}/LATEST"
  # Also store original path
  printf '%s\n' "$conf" >"${NTM_BACKUP_DIR}/CONF_PATH"
  ntm_ok "Backup created: $dest"
  printf '%s' "$dest"
}

ntm_latest_backup() {
  if [ -f "${NTM_BACKUP_DIR}/LATEST" ]; then
    cat "${NTM_BACKUP_DIR}/LATEST"
    return 0
  fi
  ls -1t "${NTM_BACKUP_DIR}"/nginx.conf.*.bak 2>/dev/null | head -n1
}

ntm_rollback_nginx_conf() {
  local conf backup
  backup="$(ntm_latest_backup)"
  if [ -z "$backup" ] || [ ! -f "$backup" ]; then
    ntm_error "No backup available to rollback"
    return 1
  fi
  if [ -f "${NTM_BACKUP_DIR}/CONF_PATH" ]; then
    conf="$(cat "${NTM_BACKUP_DIR}/CONF_PATH")"
  else
    conf="$(ntm_detect_nginx_conf)" || return 1
  fi
  cp -a "$backup" "$conf"
  ntm_ok "Restored nginx.conf from $backup → $conf"
}

ntm_nginx_test() {
  local bin conf
  bin="$(ntm_detect_nginx_bin)" || return 1
  conf="$(ntm_detect_nginx_conf 2>/dev/null || true)"
  if [ -n "$conf" ] && [ -f "$conf" ]; then
    "$bin" -t -c "$conf"
  else
    "$bin" -t
  fi
}

ntm_nginx_reload() {
  local bin conf
  bin="$(ntm_detect_nginx_bin)" || return 1
  conf="$(ntm_detect_nginx_conf 2>/dev/null || true)"
  if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet nginx 2>/dev/null; then
    systemctl reload nginx && return 0
  fi
  if [ -n "$conf" ] && [ -f "$conf" ]; then
    "$bin" -c "$conf" -s reload
  else
    "$bin" -s reload
  fi
}

# Ensure log_format traffic exists in http {} block of main conf
# Supports both `http {` and aaPanel-style `http` + `{` on next line.
ntm_ensure_log_format() {
  local conf="$1"
  local name="${NTM_LOG_FORMAT_NAME}"
  local body="${NTM_LOG_FORMAT_BODY}"

  if grep -Eq "log_format[[:space:]]+${name}[[:space:]]+" "$conf" 2>/dev/null; then
    ntm_info "log_format ${name} already present in $conf"
    return 0
  fi

  local tmp
  tmp="$(mktemp 2>/dev/null || echo "/tmp/ntm-nginx.$$")"
  awk -v name="$name" -v body="$body" '
    BEGIN { inserted=0; pending=0 }
    {
      if (!inserted && $0 ~ /^[[:space:]]*http[[:space:]]*$/) {
        print
        pending=1
        next
      }
      if (!inserted && pending && $0 ~ /^[[:space:]]*\{/) {
        print
        print "        # Added by Nginx Traffic Monitor"
        print "        log_format " name " " body ";"
        inserted=1
        pending=0
        next
      }
      pending=0
      print
      if (!inserted && $0 ~ /^[[:space:]]*http[[:space:]]*\{/) {
        print "    # Added by Nginx Traffic Monitor"
        print "    log_format " name " " body ";"
        inserted=1
      }
    }
    END {
      if (!inserted) {
        print "# WARNING: http block not found; append log_format manually" > "/dev/stderr"
      }
    }
  ' "$conf" >"$tmp"
  mv "$tmp" "$conf"
  ntm_ok "Inserted log_format ${name} into $conf"
}

# Prefer a drop-in file included by http {} (conf.d, http.d, or aaPanel vhost dir)
ntm_ensure_dropin_conf() {
  local main conf_dir dropin name body
  main="$(ntm_detect_nginx_conf)" || return 1
  conf_dir="$(dirname "$main")"
  name="${NTM_LOG_FORMAT_NAME}"
  body="${NTM_LOG_FORMAT_BODY}"

  dropin=""
  # aaPanel / BT: vhost nginx dir is included inside http {}
  if [ -d /www/server/panel/vhost/nginx ]; then
    dropin="/www/server/panel/vhost/nginx/0.ntm_traffic_log_format.conf"
  elif [ -d "${conf_dir}/conf.d" ]; then
    dropin="${conf_dir}/conf.d/00-nginx-traffic-monitor.conf"
  elif [ -d "${conf_dir}/http.d" ]; then
    dropin="${conf_dir}/http.d/00-nginx-traffic-monitor.conf"
  fi

  if [ -z "$dropin" ]; then
    ntm_info "No drop-in directory found — will use main nginx.conf"
    return 0
  fi

  cat >"$dropin" <<EOF
# Managed by Nginx Traffic Monitor — do not edit by hand
log_format ${name} ${body};
EOF
  ntm_ok "Wrote drop-in config: $dropin"
  mkdir -p "$NTM_BACKUP_DIR" 2>/dev/null || true
  printf '%s\n' "$dropin" >"${NTM_BACKUP_DIR}/DROPIN" 2>/dev/null || true
}

# Insert access_log at http {} level (safety net). Supports multiline http {
ntm_ensure_http_access_log() {
  local conf="$1"
  local log_path="${NTM_TRAFFIC_LOG}"
  local name="${NTM_LOG_FORMAT_NAME}"

  # On aaPanel, http-level "access_log off;" is common — still add our line after log_format if possible
  if grep -Eq "access_log[[:space:]]+${log_path}([[:space:]]|;)" "$conf"; then
    ntm_info "http-level access_log already present in main conf"
    return 0
  fi

  # Skip mutating main conf when aaPanel drop-in handles format and sites get per-server logs
  if [ -d /www/server/panel/vhost/nginx ]; then
    ntm_info "aaPanel detected — skipping http-level access_log in main conf (using per-vhost logs)"
    return 0
  fi

  local tmp
  tmp="$(mktemp 2>/dev/null || echo "/tmp/ntm-http-access.$$")"
  awk -v log_path="$log_path" -v name="$name" '
    BEGIN { inserted=0; pending=0 }
    {
      if (!inserted && $0 ~ /^[[:space:]]*http[[:space:]]*$/) { print; pending=1; next }
      if (!inserted && pending && $0 ~ /^[[:space:]]*\{/) {
        print
        print "        access_log " log_path " " name ";"
        print "        # http-level access_log added by Nginx Traffic Monitor"
        inserted=1; pending=0; next
      }
      pending=0
      print
      if (!inserted && $0 ~ ("log_format[[:space:]]+" name "[[:space:]]+")) {
        print "    access_log " log_path " " name ";"
        print "    # http-level access_log added by Nginx Traffic Monitor"
        inserted=1
        next
      }
      if (!inserted && $0 ~ /^[[:space:]]*http[[:space:]]*\{/) {
        print "    access_log " log_path " " name ";"
        print "    # http-level access_log added by Nginx Traffic Monitor"
        inserted=1
      }
    }
  ' "$conf" >"$tmp"
  mv "$tmp" "$conf"
  ntm_ok "Inserted http-level access_log → ${log_path}"
}

# Collect candidate config files that may contain server blocks
ntm_collect_site_files() {
  local main conf_dir sites f
  main="$(ntm_detect_nginx_conf)" || return 1
  conf_dir="$(dirname "$main")"
  printf '%s\n' "$main"

  for sites in \
    "${conf_dir}/sites-enabled" \
    "${conf_dir}/sites-available" \
    "${conf_dir}/conf.d" \
    "${conf_dir}/http.d" \
    "${conf_dir}/vhost" \
    "${conf_dir}/vhosts" \
    /www/server/panel/vhost/nginx
  do
    if [ -d "$sites" ]; then
      for f in "$sites"/*; do
        [ -f "$f" ] || continue
        case "$f" in
          *00-nginx-traffic-monitor.conf|*0.ntm_traffic_log_format.conf|*0.site_total_log_format.conf|*0.websocket.conf|*0.fastcgi_cache.conf|*waf2monitor*) continue ;;
        esac
        printf '%s\n' "$f"
      done
    fi
  done

  local bin conf
  bin="$(ntm_detect_nginx_bin 2>/dev/null || true)"
  conf="$main"
  if [ -n "$bin" ]; then
    "$bin" -T -c "$conf" 2>/dev/null | grep -E '^# configuration file ' | awk '{print $4}' | sed 's/:$//' | while IFS= read -r f; do
      [ -f "$f" ] || continue
      case "$f" in
        *00-nginx-traffic-monitor.conf|*0.ntm_traffic_log_format.conf) continue ;;
      esac
      printf '%s\n' "$f"
    done
  fi
}

# Patch one file: add traffic access_log after an existing real access_log (.log), else end of server
ntm_patch_file_access_log() {
  local f="$1"
  local log_path="${NTM_TRAFFIC_LOG}"
  local name="${NTM_LOG_FORMAT_NAME}"
  local tmp

  [ -f "$f" ] || return 0
  if grep -Eq "access_log[[:space:]]+${log_path}([[:space:]]|;)" "$f"; then
    return 0
  fi

  tmp="$(mktemp 2>/dev/null || echo "/tmp/ntm-access.$$")"
  awk -v log_path="$log_path" -v name="$name" '
    BEGIN { done=0 }
    {
      print
      if (!done && $0 ~ /access_log/ && $0 ~ /\.log;/ && $0 !~ /\/dev\/null/ && $0 !~ log_path) {
        print "    access_log " log_path " " name ";"
        print "    # access_log added by Nginx Traffic Monitor"
        done=1
      }
    }
    END {
      # If no real access_log line found, leave file unchanged (done==0)
    }
  ' "$f" >"$tmp"

  if [ "$(grep -c "access_log ${log_path} ${name}" "$tmp" 2>/dev/null || echo 0)" -eq 0 ]; then
    # Fallback: before last lone } in file
    awk -v log_path="$log_path" -v name="$name" '
      { lines[++n]=$0 }
      END {
        for (i=1;i<=n;i++) {
          if (i==n && lines[i] ~ /^[[:space:]]*\}[[:space:]]*$/) {
            print "    access_log " log_path " " name ";"
            print "    # access_log added by Nginx Traffic Monitor"
          }
          print lines[i]
        }
      }
    ' "$f" >"$tmp"
  fi

  if ! cmp -s "$f" "$tmp" 2>/dev/null; then
    mv "$tmp" "$f"
    ntm_ok "Patched access_log in $f"
    return 0
  fi
  rm -f "$tmp"
  return 0
}

ntm_ensure_access_logs() {
  local f modified=0 seen=""
  local main

  main="$(ntm_detect_nginx_conf)" || return 1
  mkdir -p "$NTM_BACKUP_DIR" 2>/dev/null || true
  ntm_ensure_dropin_conf || true
  ntm_ensure_log_format "$main" || true
  ntm_ensure_http_access_log "$main" || true

  while IFS= read -r f; do
    [ -z "$f" ] && continue
    [ -f "$f" ] || continue
    case "$seen" in
      *"|${f}|"*) continue ;;
    esac
    seen="${seen}|${f}|"

    # Must look like a vhost (listen or server_name) or contain server {
    if ! grep -Eq 'server[[:space:]]*\{|^[[:space:]]*server[[:space:]]*$|listen[[:space:]]|server_name[[:space:]]' "$f"; then
      continue
    fi

    local before after
    before="$(grep -c "access_log[[:space:]]\+${NTM_TRAFFIC_LOG}" "$f" 2>/dev/null || echo 0)"
    ntm_patch_file_access_log "$f"
    after="$(grep -c "access_log[[:space:]]\+${NTM_TRAFFIC_LOG}" "$f" 2>/dev/null || echo 0)"
    if [ "${after:-0}" -gt "${before:-0}" ]; then
      modified=$((modified + 1))
    fi
  done <<EOF
$(ntm_collect_site_files | sort -u)
EOF

  if [ "$modified" -eq 0 ]; then
    ntm_info "No per-server access_log file changes (may already be configured)"
  else
    ntm_ok "Updated access_log in ${modified} config file(s)"
  fi
}

# Confirm live nginx config references our traffic log
ntm_assert_traffic_logging_active() {
  local bin conf dump
  bin="$(ntm_detect_nginx_bin)" || return 1
  conf="$(ntm_detect_nginx_conf 2>/dev/null || true)"
  if [ -n "$conf" ]; then
    dump="$("$bin" -T -c "$conf" 2>/dev/null || true)"
  else
    dump="$("$bin" -T 2>/dev/null || true)"
  fi
  if printf '%s\n' "$dump" | grep -Eq "log_format[[:space:]]+${NTM_LOG_FORMAT_NAME}[[:space:]]+"; then
    ntm_ok "nginx -T: log_format ${NTM_LOG_FORMAT_NAME} active"
  else
    ntm_warn "nginx -T: log_format ${NTM_LOG_FORMAT_NAME} NOT found in live config"
    return 1
  fi
  if printf '%s\n' "$dump" | grep -Eq "access_log[[:space:]]+${NTM_TRAFFIC_LOG}"; then
    local count
    count="$(printf '%s\n' "$dump" | grep -cE "access_log[[:space:]]+${NTM_TRAFFIC_LOG}" || true)"
    ntm_ok "nginx -T: access_log ${NTM_TRAFFIC_LOG} active (${count} directive(s))"
  else
    ntm_error "nginx -T: access_log ${NTM_TRAFFIC_LOG} NOT found — traffic will not be recorded"
    ntm_info "Run: sudo $bin -T -c ${conf:-/etc/nginx/nginx.conf} 2>/dev/null | grep -E 'traffic'"
    return 1
  fi
  return 0
}

ntm_ensure_traffic_log_file() {
  local log_path="${NTM_TRAFFIC_LOG}"
  local owner group
  mkdir -p "$(dirname "$log_path")"
  touch "$log_path"
  owner="${NTM_LOG_OWNER:-$(ntm_nginx_worker_user)}"
  group="${NTM_LOG_GROUP:-adm}"

  if id "$owner" >/dev/null 2>&1; then
    if getent group "$group" >/dev/null 2>&1; then
      chown "${owner}:${group}" "$log_path" 2>/dev/null || chown "$owner" "$log_path" 2>/dev/null || true
    else
      chown "$owner" "$log_path" 2>/dev/null || true
    fi
  fi
  chmod 644 "$log_path" 2>/dev/null || chmod 640 "$log_path" 2>/dev/null || true
  # Ensure worker can write (common cause of empty logs)
  if id "$owner" >/dev/null 2>&1; then
    if ! su -s /bin/sh "$owner" -c "test -w '$log_path'" 2>/dev/null; then
      chown "$owner" "$log_path" 2>/dev/null || true
      chmod 644 "$log_path" 2>/dev/null || true
      if su -s /bin/sh "$owner" -c "test -w '$log_path'" 2>/dev/null; then
        ntm_ok "Log is writable by ${owner}"
      else
        ntm_warn "Log may not be writable by nginx worker '${owner}' — check: ls -la $log_path"
      fi
    else
      ntm_ok "Log is writable by ${owner}"
    fi
  fi
  ntm_ok "Traffic log ready: $log_path (owner ${owner})"
}

# Remove traffic log_format and access_log lines (best-effort; prefer backup restore)
ntm_remove_traffic_directives() {
  local conf main
  main="$(ntm_detect_nginx_conf)" || return 1
  local log_path="${NTM_TRAFFIC_LOG}"
  local name="${NTM_LOG_FORMAT_NAME}"

  if [ -f "${NTM_BACKUP_DIR}/DROPIN" ]; then
    local dropin
    dropin="$(cat "${NTM_BACKUP_DIR}/DROPIN")"
    if [ -n "$dropin" ] && [ -f "$dropin" ]; then
      rm -f "$dropin"
      ntm_ok "Removed drop-in $dropin"
    fi
  fi
  rm -f "$(dirname "$main")/conf.d/00-nginx-traffic-monitor.conf" 2>/dev/null || true
  rm -f "$(dirname "$main")/http.d/00-nginx-traffic-monitor.conf" 2>/dev/null || true
  rm -f /www/server/panel/vhost/nginx/0.ntm_traffic_log_format.conf 2>/dev/null || true

  local f
  for f in "$main" \
    "$(dirname "$main")/sites-enabled"/* \
    "$(dirname "$main")/sites-available"/* \
    "$(dirname "$main")/conf.d"/* \
    "$(dirname "$main")/http.d"/*
  do
    [ -f "$f" ] || continue
    local tmp
    tmp="$(mktemp 2>/dev/null || echo "/tmp/ntm-rm.$$")"
    grep -Ev "log_format[[:space:]]+${name}[[:space:]]+" "$f" \
      | grep -Ev "access_log[[:space:]]+${log_path}" \
      | grep -Ev "Added by Nginx Traffic Monitor|access_log added by Nginx Traffic Monitor|http-level access_log added by Nginx Traffic Monitor|Managed by Nginx Traffic Monitor" \
      >"$tmp" || true
    mv "$tmp" "$f"
  done
}

# Full install / verify path
ntm_install_traffic_logging() {
  ntm_require_root || return 1

  local bin conf
  bin="$(ntm_detect_nginx_bin)" || {
    ntm_error "nginx binary not found"
    ntm_info "Install nginx or set: sudo NTM_NGINX_BIN=/path/to/nginx ./install.sh"
    return 1
  }
  conf="$(ntm_detect_nginx_conf)" || {
    ntm_error "nginx.conf not found"
    ntm_info "nginx binary: $bin"
    ntm_info "Checked: NTM_NGINX_CONF, nginx -V --conf-path, nginx -t, --prefix, known paths, find under /etc /usr/local /opt /www"
    ntm_info "Override manually: sudo NTM_NGINX_CONF=/path/to/nginx.conf ./install.sh"
    return 1
  }

  ntm_info "nginx binary: $bin"
  ntm_info "nginx.conf:   $conf"

  ntm_backup_nginx_conf >/dev/null || return 1
  ntm_ensure_access_logs || return 1
  ntm_ensure_traffic_log_file || return 1

  if ! ntm_nginx_test; then
    ntm_error "nginx -t failed — rolling back"
    ntm_rollback_nginx_conf
    return 1
  fi

  if ! ntm_nginx_reload; then
    ntm_error "nginx reload failed — rolling back"
    ntm_rollback_nginx_conf
    ntm_nginx_test >/dev/null 2>&1 || true
    return 1
  fi

  if ! ntm_assert_traffic_logging_active; then
    ntm_warn "Install finished but live config check failed — traffic may not be recorded"
    ntm_info "Fix: ensure access_log ${NTM_TRAFFIC_LOG} ${NTM_LOG_FORMAT_NAME}; is in http{} or every active server{}"
  fi

  ntm_run_hooks on_install
  ntm_ok "Nginx Traffic Monitor logging installed successfully"
  ntm_info "Send a real HTTP request, then: sudo tail -f ${NTM_TRAFFIC_LOG}"
}

ntm_verify_installation() {
  ntm_title "Verify Installation"
  local bin conf ok=1 lines=0 bytes=0 owner
  if bin="$(ntm_detect_nginx_bin)"; then
    ntm_ok "nginx binary: $bin"
  else
    ntm_error "nginx binary missing"
    ok=0
  fi
  if conf="$(ntm_detect_nginx_conf)"; then
    ntm_ok "nginx.conf: $conf"
  else
    ntm_error "nginx.conf missing"
    ok=0
  fi

  # Prefer live config (nginx -T) over file greps
  if [ -n "${bin:-}" ]; then
    if ntm_assert_traffic_logging_active; then
      :
    else
      ok=0
      # Fall back to main conf file check for hints
      if [ -n "${conf:-}" ] && grep -Eq "log_format[[:space:]]+${NTM_LOG_FORMAT_NAME}[[:space:]]+" "$conf"; then
        ntm_info "log_format exists in $conf but may not be loaded — check includes"
      fi
    fi
  fi

  if [ -e "$NTM_TRAFFIC_LOG" ]; then
    ntm_ok "traffic log exists: $NTM_TRAFFIC_LOG"
    bytes="$(stat -c '%s' "$NTM_TRAFFIC_LOG" 2>/dev/null || stat -f '%z' "$NTM_TRAFFIC_LOG" 2>/dev/null || echo 0)"
    lines="$(wc -l <"$NTM_TRAFFIC_LOG" 2>/dev/null | tr -d ' ' || echo 0)"
    owner="$(stat -c '%U:%G' "$NTM_TRAFFIC_LOG" 2>/dev/null || stat -f '%Su:%Sg' "$NTM_TRAFFIC_LOG" 2>/dev/null || echo unknown)"
    ntm_info "log size: ${bytes} bytes, ${lines} lines, owner ${owner}"

    local worker
    worker="$(ntm_nginx_worker_user)"
    if [ -r "$NTM_TRAFFIC_LOG" ]; then
      local last
      last="$(tail -n1 "$NTM_TRAFFIC_LOG" 2>/dev/null || true)"
      if [ -n "$last" ]; then
        ntm_ok "last log line: $last"
      else
        ntm_error "traffic log is EMPTY — nginx is not writing requests here"
        ntm_info "Checklist:"
        ntm_info "  1) sudo nginx -T 2>/dev/null | grep -E 'log_format traffic|traffic.log'"
        ntm_info "  2) Re-run: sudo ./install.sh"
        ntm_info "  3) Hit the site, then: sudo tail -f $NTM_TRAFFIC_LOG"
        ntm_info "  4) Check permissions for worker user '${worker}': ls -la $NTM_TRAFFIC_LOG"
        ntm_info "  5) sudo tail -n 50 /var/log/nginx/error.log"
        ok=0
      fi
    else
      ntm_warn "traffic log exists but is not readable by current user"
      ok=0
    fi
  else
    ntm_warn "traffic log missing: $NTM_TRAFFIC_LOG"
    ok=0
  fi

  if [ -n "${bin:-}" ] && "$bin" -t 2>/dev/null; then
    ntm_ok "nginx -t passed"
  else
    ntm_warn "nginx -t failed or unavailable"
    ok=0
  fi
  [ "$ok" -eq 1 ]
}

ntm_uninstall_traffic_logging() {
  ntm_require_root || return 1
  ntm_title "Uninstall Nginx Traffic Monitor hooks"

  if ! ntm_confirm "Restore nginx.conf from backup and remove traffic logging? [y/N] "; then
    ntm_info "Uninstall cancelled"
    return 0
  fi

  if ntm_latest_backup >/dev/null 2>&1 && [ -n "$(ntm_latest_backup)" ]; then
    ntm_rollback_nginx_conf || return 1
  else
    ntm_warn "No backup found — attempting directive cleanup"
    ntm_remove_traffic_directives
  fi

  if ! ntm_nginx_test; then
    ntm_error "nginx -t failed after uninstall changes"
    return 1
  fi
  ntm_nginx_reload || ntm_warn "reload failed — config test passed; reload manually"
  ntm_run_hooks on_uninstall
  ntm_ok "Uninstall complete (rotated logs were preserved)"
}

ntm_reset_traffic_log() {
  ntm_require_root || return 1
  local log_path="${NTM_TRAFFIC_LOG}"
  if [ ! -e "$log_path" ]; then
    ntm_warn "Log does not exist yet: $log_path"
    ntm_ensure_traffic_log_file
    return 0
  fi
  if ! ntm_confirm "Rotate $log_path now? [y/N] "; then
    ntm_info "Reset cancelled"
    return 0
  fi
  local dest="${log_path}.$(ntm_timestamp)"
  mv "$log_path" "$dest"
  ntm_ensure_traffic_log_file
  ntm_ok "Rotated log to $dest"
}
