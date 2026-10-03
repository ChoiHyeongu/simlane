#!/usr/bin/env bash
# simlane env [--json] — lane variables for the current directory. Hooks pipe this straight into CLAUDE_ENV_FILE, so it never fails.

cmd_env() {
  local json=0 reserved wt lane port udid bundle project obj
  [ "${1:-}" = --json ] && json=1
  reserved=$(simlane::sim_reserved_udids 2>/dev/null || true)
  obj=$(jq -cn --arg r "$reserved" '{SIMLANE_RESERVED_UDIDS: $r}')
  if git rev-parse --show-toplevel >/dev/null 2>&1 && simlane::wt_is_worktree; then
    wt=$(simlane::wt_toplevel)
    lane=$(simlane::registry_find_by_worktree "$wt")
    if [ -n "$lane" ]; then
      port=$(simlane::metro_port "$lane")
      udid=$(simlane::sim_find_udid "$(simlane::sim_name "$lane")" 2>/dev/null || true)
      bundle=$(simlane::registry_get "$lane" bundleId)
      project=$(simlane::registry_get "$lane" project)
      obj=$(jq -cn --arg r "$reserved" --arg s "$lane" --arg p "$port" --arg u "$udid" --arg b "$bundle" --arg pr "$project" \
        '{SIMLANE_LANE:$s, SIMLANE_METRO_PORT:$p, SIMLANE_SIM_UDID:$u, SIMLANE_BUNDLE_ID:$b, SIMLANE_PROJECT:$pr, SIMLANE_RESERVED_UDIDS:$r}')
    else
      # Worktree without a lane: hooks only append, so export empty values to override a previous session's variables.
      obj=$(jq -cn --arg r "$reserved" '{SIMLANE_LANE:"", SIMLANE_METRO_PORT:"", SIMLANE_SIM_UDID:"", SIMLANE_BUNDLE_ID:"", SIMLANE_PROJECT:"", SIMLANE_RESERVED_UDIDS:$r}')
    fi
  fi
  if [ "$json" -eq 1 ]; then
    printf '%s\n' "$obj"
  else
    jq -r 'to_entries[] | "export \(.key)=\(.value|@sh)"' <<<"$obj"
  fi
  return 0
}
