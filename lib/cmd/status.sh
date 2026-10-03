#!/usr/bin/env bash
# simlane status — live probes (simctl list, tmux has-session, GET /status), not the registry.

cmd_status() {
  local max s port udid state metro wt
  max=$(simlane::config_get .maxLanes)
  printf '%-5s %-6s %-10s %-13s %s\n' LANE PORT SIM METRO WORKTREE
  s=1
  while [ "$s" -le "$max" ]; do
    port=$(simlane::metro_port "$s")
    udid=$(simlane::sim_find_udid "$(simlane::sim_name "$s")" 2>/dev/null || true)
    if [ -n "$udid" ]; then state=$(simlane::sim_state "$udid"); else state="-"; fi
    metro=$(simlane::metro_status "$port")
    if simlane::metro_running "$s"; then metro="$metro/tmux"; fi
    wt=$(simlane::registry_get "$s" worktree); [ -n "$wt" ] || wt="-"
    printf '%-5s %-6s %-10s %-13s %s\n' "$s" "$port" "$state" "$metro" "$wt"
    s=$((s + 1))
  done
}
