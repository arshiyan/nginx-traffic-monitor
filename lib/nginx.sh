#!/usr/bin/env bash
# nginx.sh — detect nginx, backup/restore conf, install traffic logging, validate, reload

[ -n "${NTM_NGINX_LOADED:-}" ] && return 0
NTM_NGINX_LOADED=1

ntm_detect_nginx_bin() {
  if [ -n "${NTM_NGINX_BIN:-}" ] && [ -x "$NTM_NGINX_BIN" ]; then
    printf '%s' "$NTM_NGINX_BIN"
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

ntm_detect_nginx_conf() {
  if [ -n "${NTM_NGINX_CONF:-}" ] && [ -f "$NTM_NGINX_CONF" ]; then
    printf '%s' "$NTM_NGINX_CONF"
    return 0
  fi
  local bin conf
  bin="$(ntm_detect_nginx_bin 2>/dev/null || true)"
  if [ -n "$bin" ]; then
    conf="$("$bin" -V 2>&1 | tr ' ' '\n' | grep -E '^--conf-path=' | head -n1 | cut -d= -f2- || true)"
    if [ -n "$conf" ] && [ -f "$conf" ]; then
      printf '%s' "$conf"
      return 0
    fi
  fi
  for p in /etc/nginx/nginx.conf /usr/local/nginx/conf/nginx.conf /opt/nginx/conf/nginx.conf; do
    if [ -f "$p" ]; then
      printf '%s' "$p"
      return 0
    fi
  done
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
  local bin
  bin="$(ntm_detect_nginx_bin)" || return 1
  "$bin" -t
}

ntm_nginx_reload() {
  local bin
  bin="$(ntm_detect_nginx_bin)" || return 1
  if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet nginx 2>/dev/null; then
    systemctl reload nginx
  else
    "$bin" -s reload
  fi
}

# Ensure log_format traffic exists in http {} block of main conf
ntm_ensure_log_format() {
  local conf="$1"
  local name="${NTM_LOG_FORMAT_NAME}"
  local body="${NTM_LOG_FORMAT_BODY}"

  if grep -Eq "log_format[[:space:]]+${name}[[:space:]]+" "$conf"; then
    ntm_info "log_format ${name} already present"
    return 0
  fi

  # Insert after the opening http { line
  local tmp
  tmp="$(mktemp 2>/dev/null || echo "/tmp/ntm-nginx.$$")"
  awk -v name="$name" -v body="$body" '
    BEGIN { inserted=0 }
    {
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
  ntm_ok "Inserted log_format ${name}"
}

# Append access_log to each enabled server block that lacks traffic.log
ntm_ensure_access_logs() {
  local conf_dir sites
  conf_dir="$(dirname "$(ntm_detect_nginx_conf)")"
  local log_path="${NTM_TRAFFIC_LOG}"
  local name="${NTM_LOG_FORMAT_NAME}"
  local directive="    access_log ${log_path} ${name};"

  # Candidate files: sites-enabled and conf.d
  local files=""
  for sites in \
    "${conf_dir}/sites-enabled" \
    "${conf_dir}/conf.d" \
    "${conf_dir}/http.d"
  do
    if [ -d "$sites" ]; then
      for f in "$sites"/*; do
        [ -f "$f" ] || continue
        files="${files}${f}"$'\n'
      done
    fi
  done

  # Always also check main conf for server blocks
  local main
  main="$(ntm_detect_nginx_conf)"
  files="${files}${main}"$'\n'

  local f modified=0
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    [ -f "$f" ] || continue
    # Skip if already has traffic access_log
    if grep -Eq "access_log[[:space:]]+${log_path}([[:space:]]|\;)" "$f"; then
      ntm_info "access_log already set in $f"
      continue
    fi
    # Only modify files that contain a server { block
    if ! grep -Eq 'server[[:space:]]*\{' "$f"; then
      continue
    fi
    # Append before each closing of server is hard; append once before last }
    # Safer approach: append directive inside first server block after the opening brace
    local tmp
    tmp="$(mktemp 2>/dev/null || echo "/tmp/ntm-access.$$")"
    awk -v dir="$directive" '
      BEGIN { done=0 }
      {
        print
        if (!done && $0 ~ /server[[:space:]]*\{/) {
          print dir
          print "    # access_log added by Nginx Traffic Monitor"
          done=1
        }
      }
    ' "$f" >"$tmp"
    if ! cmp -s "$f" "$tmp" 2>/dev/null; then
      mv "$tmp" "$f"
      modified=$((modified + 1))
      ntm_ok "Added access_log to $f"
    else
      rm -f "$tmp"
    fi
  done <<EOF
$files
EOF

  if [ "$modified" -eq 0 ]; then
    ntm_info "No new access_log directives were required"
  fi
}

ntm_ensure_traffic_log_file() {
  local log_path="${NTM_TRAFFIC_LOG}"
  local owner group
  mkdir -p "$(dirname "$log_path")"
  touch "$log_path"
  owner="${NTM_LOG_OWNER:-$(ntm_nginx_worker_user)}"
  group="${NTM_LOG_GROUP:-adm}"
  if id "$owner" >/dev/null 2>&1; then
    chown "${owner}:${group}" "$log_path" 2>/dev/null || chown "$owner" "$log_path" 2>/dev/null || true
  fi
  chmod 640 "$log_path" 2>/dev/null || chmod 644 "$log_path" 2>/dev/null || true
  ntm_ok "Traffic log ready: $log_path (owner ${owner})"
}

# Remove traffic log_format and access_log lines (best-effort; prefer backup restore)
ntm_remove_traffic_directives() {
  local conf main
  main="$(ntm_detect_nginx_conf)" || return 1
  local log_path="${NTM_TRAFFIC_LOG}"
  local name="${NTM_LOG_FORMAT_NAME}"

  local f
  for f in "$main" \
    "$(dirname "$main")/sites-enabled"/* \
    "$(dirname "$main")/conf.d"/* \
    "$(dirname "$main")/http.d"/*
  do
    [ -f "$f" ] || continue
    local tmp
    tmp="$(mktemp 2>/dev/null || echo "/tmp/ntm-rm.$$")"
    grep -Ev "log_format[[:space:]]+${name}[[:space:]]+" "$f" \
      | grep -Ev "access_log[[:space:]]+${log_path}" \
      | grep -Ev "Added by Nginx Traffic Monitor|access_log added by Nginx Traffic Monitor" \
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
    return 1
  }
  conf="$(ntm_detect_nginx_conf)" || {
    ntm_error "nginx.conf not found"
    return 1
  }

  ntm_info "nginx binary: $bin"
  ntm_info "nginx.conf:   $conf"

  ntm_backup_nginx_conf >/dev/null || return 1
  ntm_ensure_log_format "$conf" || return 1
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

  ntm_run_hooks on_install
  ntm_ok "Nginx Traffic Monitor logging installed successfully"
}

ntm_verify_installation() {
  ntm_title "Verify Installation"
  local bin conf ok=1
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
  if [ -n "${conf:-}" ] && grep -Eq "log_format[[:space:]]+${NTM_LOG_FORMAT_NAME}[[:space:]]+" "$conf"; then
    ntm_ok "log_format ${NTM_LOG_FORMAT_NAME} present"
  else
    ntm_warn "log_format ${NTM_LOG_FORMAT_NAME} not found in main conf"
    ok=0
  fi
  if [ -e "$NTM_TRAFFIC_LOG" ]; then
    ntm_ok "traffic log exists: $NTM_TRAFFIC_LOG"
    if [ -r "$NTM_TRAFFIC_LOG" ]; then
      local last
      last="$(tail -n1 "$NTM_TRAFFIC_LOG" 2>/dev/null || true)"
      if [ -n "$last" ]; then
        ntm_ok "last log line: $last"
      else
        ntm_info "traffic log is empty (waiting for requests)"
      fi
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
