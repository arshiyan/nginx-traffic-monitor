#!/usr/bin/env bash
# plugin_loader.sh — discover, validate, enable/disable, and load plugins

[ -n "${NTM_LOADER_LOADED:-}" ] && return 0
NTM_LOADER_LOADED=1

# Read enable flag from config/plugins.enabled (empty = unset)
ntm_plugin_enabled_override() {
  local id="$1"
  local file="${NTM_PLUGINS_ENABLED_FILE}"
  [ -f "$file" ] || return 1
  local line
  line="$(grep -E "^${id}=" "$file" 2>/dev/null | tail -n1 || true)"
  [ -n "$line" ] || return 1
  printf '%s' "${line#*=}"
}

ntm_set_plugin_enabled() {
  local id="$1"
  local val="$2"
  local file="${NTM_PLUGINS_ENABLED_FILE}"
  local tmp
  mkdir -p "$(dirname "$file")"
  touch "$file"
  tmp="$(mktemp 2>/dev/null || echo "/tmp/ntm-plugins.$$")"
  if grep -qE "^${id}=" "$file" 2>/dev/null; then
    sed "s/^${id}=.*/${id}=${val}/" "$file" >"$tmp"
  else
    cat "$file" >"$tmp"
    printf '%s=%s\n' "$id" "$val" >>"$tmp"
  fi
  mv "$tmp" "$file"
}

# Rename a function safely: old_name -> new_name
_ntm_rename_func() {
  local old="$1"
  local new="$2"
  if ! declare -F "$old" >/dev/null 2>&1; then
    return 1
  fi
  eval "$(declare -f "$old" | sed "1s/^${old}[[:space:]]*()/ ${new}()/")"
  unset -f "$old" 2>/dev/null || true
}

# Load a single plugin directory; never aborts the whole app on failure
ntm_load_plugin_dir() {
  local dir="$1"
  local conf="${dir}/plugin.conf"
  local script="${dir}/plugin.sh"
  local PLUGIN_ID PLUGIN_NAME PLUGIN_DESC PLUGIN_VERSION
  local PLUGIN_MENU_LABEL PLUGIN_CLI_FLAGS PLUGIN_ENABLED
  local PLUGIN_REQUIRES_ROOT PLUGIN_PRIORITY PLUGIN_HIDE_MENU

  if [ ! -f "$conf" ] || [ ! -f "$script" ]; then
    return 0
  fi

  PLUGIN_ID=""
  PLUGIN_NAME=""
  PLUGIN_DESC=""
  PLUGIN_VERSION="0.0.0"
  PLUGIN_MENU_LABEL=""
  PLUGIN_CLI_FLAGS=""
  PLUGIN_ENABLED=1
  PLUGIN_REQUIRES_ROOT=0
  PLUGIN_PRIORITY=100
  PLUGIN_HIDE_MENU=0

  # shellcheck disable=SC1090
  if ! . "$conf"; then
    ntm_warn "Failed to read plugin.conf: $conf"
    return 0
  fi

  if [ -z "$PLUGIN_ID" ]; then
    ntm_warn "Plugin missing PLUGIN_ID in $conf"
    return 0
  fi

  local override
  override="$(ntm_plugin_enabled_override "$PLUGIN_ID" || true)"
  if [ -n "$override" ]; then
    PLUGIN_ENABLED="$override"
  fi

  ntm_register_plugin_meta "$PLUGIN_ID" "${PLUGIN_NAME:-$PLUGIN_ID}" "$dir" "$PLUGIN_ENABLED"

  if [ "$PLUGIN_ENABLED" != "1" ]; then
    return 0
  fi

  NTM_CURRENT_PLUGIN_ID="$PLUGIN_ID"
  NTM_CURRENT_PLUGIN_DIR="$dir"

  local safe_id
  safe_id="$(printf '%s' "$PLUGIN_ID" | tr -c 'A-Za-z0-9_' '_')"

  # shellcheck disable=SC1090
  if ! . "$script"; then
    ntm_warn "Failed to source plugin: $script"
    NTM_CURRENT_PLUGIN_ID=""
    NTM_CURRENT_PLUGIN_DIR=""
    return 0
  fi

  # Capture functions under unique names (copy body, then unset generics)
  if declare -F plugin_run >/dev/null 2>&1; then
    _ntm_rename_func plugin_run "ntm_plug_${safe_id}_run_inner"
    eval "ntm_plug_${safe_id}_run() {
      NTM_CURRENT_PLUGIN_ID=\"${PLUGIN_ID}\"
      NTM_CURRENT_PLUGIN_DIR=\"${dir}\"
      ntm_plug_${safe_id}_run_inner \"\$@\"
    }"
  fi
  if declare -F plugin_init >/dev/null 2>&1; then
    _ntm_rename_func plugin_init "ntm_plug_${safe_id}_init"
  fi
  if declare -F plugin_help >/dev/null 2>&1; then
    _ntm_rename_func plugin_help "ntm_plug_${safe_id}_help"
  fi

  # Call init if available
  if declare -F "ntm_plug_${safe_id}_init" >/dev/null 2>&1; then
    NTM_CURRENT_PLUGIN_ID="$PLUGIN_ID"
    NTM_CURRENT_PLUGIN_DIR="$dir"
    "ntm_plug_${safe_id}_init" || ntm_warn "plugin_init failed for $PLUGIN_ID"
  fi

  # Auto-register menu if label set and not hidden
  if [ -n "$PLUGIN_MENU_LABEL" ] && [ "$PLUGIN_HIDE_MENU" != "1" ]; then
    if declare -F "ntm_plug_${safe_id}_run" >/dev/null 2>&1; then
      ntm_register_menu "$PLUGIN_ID" "$PLUGIN_MENU_LABEL" "ntm_plug_${safe_id}_run" "$PLUGIN_PRIORITY"
    fi
  fi

  # Auto-register CLI flags (pipe-separated)
  if [ -n "$PLUGIN_CLI_FLAGS" ] && declare -F "ntm_plug_${safe_id}_run" >/dev/null 2>&1; then
    local flag
    local oldifs="$IFS"
    IFS='|'
    # shellcheck disable=SC2086
    for flag in $PLUGIN_CLI_FLAGS; do
      IFS="$oldifs"
      flag="$(printf '%s' "$flag" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      [ -n "$flag" ] && ntm_register_cli "$PLUGIN_ID" "$flag" "ntm_plug_${safe_id}_run"
      IFS='|'
    done
    IFS="$oldifs"
  fi

  NTM_CURRENT_PLUGIN_ID=""
  NTM_CURRENT_PLUGIN_DIR=""
}

# Discover plugins: plugins/*/ and plugins/examples/*/
ntm_load_all_plugins() {
  local d
  ntm_registry_reset

  if [ ! -d "$NTM_PLUGINS_DIR" ]; then
    ntm_warn "Plugins directory missing: $NTM_PLUGINS_DIR"
    return 0
  fi

  for d in "$NTM_PLUGINS_DIR"/[0-9]*; do
    [ -d "$d" ] || continue
    ntm_load_plugin_dir "$d"
  done

  if [ -d "$NTM_PLUGINS_DIR/examples" ]; then
    for d in "$NTM_PLUGINS_DIR/examples"/[0-9]*; do
      [ -d "$d" ] || continue
      ntm_load_plugin_dir "$d"
    done
  fi
}

ntm_plugins_list() {
  local i=0 id name dir en
  ntm_title "Installed Plugins"
  if [ -z "$NTM_PLUGIN_IDS" ]; then
    ntm_info "No plugins discovered."
    return 0
  fi
  printf '%-20s %-28s %-8s %s\n' "ID" "NAME" "ENABLED" "PATH"
  ntm_hr "-"
  while IFS= read -r id; do
    i=$((i + 1))
    name="$(printf '%s\n' "$NTM_PLUGIN_NAMES" | sed -n "${i}p")"
    dir="$(printf '%s\n' "$NTM_PLUGIN_DIRS" | sed -n "${i}p")"
    en="$(printf '%s\n' "$NTM_PLUGIN_ENABLED_FLAGS" | sed -n "${i}p")"
    printf '%-20s %-28s %-8s %s\n' "$id" "$name" "$en" "$dir"
  done <<EOF
$NTM_PLUGIN_IDS
EOF
}
