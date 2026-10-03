#!/usr/bin/env bash
# simlane down [N|--all] — release lanes. Only the named lanes are touched; the bundle address is deleted so no stale value survives.

cmd_down() {
  local target=${1:-} lanes s udid bundleId key
  if [ "$target" = --all ]; then
    lanes=$(simlane::registry_lanes)
  elif [ -n "$target" ]; then
    lanes=$target
  else
    simlane::wt_is_worktree || simlane::die "$SIMLANE_EXIT_MAIN" "not in a worktree: specify a lane number with 'simlane down <N>'"
    lanes=$(simlane::registry_find_by_worktree "$(simlane::wt_toplevel)")
    if [ -z "$lanes" ]; then simlane::log "no lane is assigned to this worktree"; return 0; fi
  fi
  for s in $lanes; do
    simlane::metro_stop "$s"
    udid=$(simlane::sim_find_udid "$(simlane::sim_name "$s")" 2>/dev/null || true)
    bundleId=$(simlane::registry_get "$s" bundleId)
    key=$(simlane::registry_get "$s" jsLocationKey)
    if [ -n "$udid" ]; then
      if [ -n "$bundleId" ] && [ "$(simlane::sim_state "$udid")" = Booted ]; then
        simlane::sim_defaults_delete "$udid" "$bundleId" "${key:-RCT_jsLocation}"
      fi
      simlane::sim_shutdown "$udid"
    fi
    simlane::lock_acquire registry 30
    simlane::registry_release "$s"
    simlane::lock_release registry
    simlane::log "released lane $s"
  done
}
