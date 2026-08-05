#!/usr/bin/env bash
# plugin_registry.sh — in-memory registries for menu items, CLI flags, hooks

[ -n "${NTM_REGISTRY_LOADED:-}" ] && return 0
NTM_REGISTRY_LOADED=1

# Parallel arrays (bash 3+ compatible style via newline-delimited strings)
NTM_MENU_IDS=""
NTM_MENU_LABELS=""
NTM_MENU_FUNCS=""
NTM_MENU_PRIORITIES=""

NTM_CLI_FLAGS=""
NTM_CLI_IDS=""
NTM_CLI_FUNCS=""

NTM_PLUGIN_IDS=""
NTM_PLUGIN_NAMES=""
NTM_PLUGIN_DIRS=""
NTM_PLUGIN_ENABLED_FLAGS=""

ntm_registry_reset() {
  NTM_MENU_IDS=""
  NTM_MENU_LABELS=""
  NTM_MENU_FUNCS=""
  NTM_MENU_PRIORITIES=""
  NTM_CLI_FLAGS=""
  NTM_CLI_IDS=""
  NTM_CLI_FUNCS=""
  NTM_PLUGIN_IDS=""
  NTM_PLUGIN_NAMES=""
  NTM_PLUGIN_DIRS=""
  NTM_PLUGIN_ENABLED_FLAGS=""
}

# Append a line to a newline-delimited string variable (by name)
_ntm_append() {
  local var="$1"
  local val="$2"
  local cur
  eval "cur=\${$var}"
  if [ -z "$cur" ]; then
    eval "$var=\"\$val\""
  else
    eval "$var=\"\$cur\"\$'\\n'\"\$val\""
  fi
}

ntm_register_plugin_meta() {
  local id="$1" name="$2" dir="$3" enabled="$4"
  _ntm_append NTM_PLUGIN_IDS "$id"
  _ntm_append NTM_PLUGIN_NAMES "$name"
  _ntm_append NTM_PLUGIN_DIRS "$dir"
  _ntm_append NTM_PLUGIN_ENABLED_FLAGS "$enabled"
}

# ntm_register_menu ID LABEL FUNC [PRIORITY]
ntm_register_menu() {
  local id="$1" label="$2" func="$3" prio="${4:-100}"
  _ntm_append NTM_MENU_IDS "$id"
  _ntm_append NTM_MENU_LABELS "$label"
  _ntm_append NTM_MENU_FUNCS "$func"
  _ntm_append NTM_MENU_PRIORITIES "$prio"
}

# ntm_register_cli ID FLAG FUNC
ntm_register_cli() {
  local id="$1" flag="$2" func="$3"
  _ntm_append NTM_CLI_IDS "$id"
  _ntm_append NTM_CLI_FLAGS "$flag"
  _ntm_append NTM_CLI_FUNCS "$func"
}

# Count menu entries
ntm_menu_count() {
  if [ -z "$NTM_MENU_IDS" ]; then
    printf '0'
    return 0
  fi
  printf '%s\n' "$NTM_MENU_IDS" | grep -c .
}

# Print sorted menu index lines: INDEX|ID|LABEL|FUNC|PRIO
ntm_menu_sorted_lines() {
  local i=0
  local id label func prio
  if [ -z "$NTM_MENU_IDS" ]; then
    return 0
  fi
  # Build sortable lines: priority|id|label|func
  while IFS= read -r id; do
    i=$((i + 1))
    label="$(printf '%s\n' "$NTM_MENU_LABELS" | sed -n "${i}p")"
    func="$(printf '%s\n' "$NTM_MENU_FUNCS" | sed -n "${i}p")"
    prio="$(printf '%s\n' "$NTM_MENU_PRIORITIES" | sed -n "${i}p")"
    printf '%05d|%s|%s|%s\n' "$prio" "$id" "$label" "$func"
  done <<EOF
$NTM_MENU_IDS
EOF
}

# Get menu func by display number (1-based after sort)
ntm_menu_get_func() {
  local num="$1"
  ntm_menu_sorted_lines | sort -t'|' -k1,1n | sed -n "${num}p" | cut -d'|' -f4
}

ntm_menu_get_id() {
  local num="$1"
  ntm_menu_sorted_lines | sort -t'|' -k1,1n | sed -n "${num}p" | cut -d'|' -f2
}

ntm_menu_get_label() {
  local num="$1"
  ntm_menu_sorted_lines | sort -t'|' -k1,1n | sed -n "${num}p" | cut -d'|' -f3
}

# Find CLI handler by flag string (exact match on registered flag token)
ntm_cli_find_func() {
  local want="$1"
  local i=0 flag func
  if [ -z "$NTM_CLI_FLAGS" ]; then
    return 1
  fi
  while IFS= read -r flag; do
    i=$((i + 1))
    if [ "$flag" = "$want" ]; then
      printf '%s\n' "$NTM_CLI_FUNCS" | sed -n "${i}p"
      return 0
    fi
  done <<EOF
$NTM_CLI_FLAGS
EOF
  return 1
}
