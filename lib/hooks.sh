#!/usr/bin/env bash
# hooks.sh — lifecycle hook registration and dispatch

[ -n "${NTM_HOOKS_LOADED:-}" ] && return 0
NTM_HOOKS_LOADED=1

# Map of hook_name -> newline-separated function names
# Stored as NTM_HOOK__<name>

ntm_register_hook() {
  local hook="$1"
  local fn="$2"
  local var="NTM_HOOK__${hook}"
  local cur
  eval "cur=\${$var:-}"
  if [ -z "$cur" ]; then
    eval "$var=\"\$fn\""
  else
    eval "$var=\"\$cur\"\$'\\n'\"\$fn\""
  fi
}

# Run all callbacks registered for a hook; arguments after hook name are passed through
ntm_run_hooks() {
  local hook="$1"
  shift
  local var="NTM_HOOK__${hook}"
  local list fn
  eval "list=\${$var:-}"
  [ -z "$list" ] && return 0
  while IFS= read -r fn; do
    [ -z "$fn" ] && continue
    if declare -F "$fn" >/dev/null 2>&1; then
      "$fn" "$@" || ntm_warn "Hook $hook callback failed: $fn"
    else
      ntm_warn "Hook $hook missing function: $fn"
    fi
  done <<EOF
$list
EOF
}
