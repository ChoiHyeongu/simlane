#!/usr/bin/env bash
# simlane metro logs|restart [N]

cmd_metro() {
  local sub=${1:-} lane=${2:-} wt main pj
  if [ -z "$lane" ]; then
    simlane::wt_is_worktree || simlane::die "$SIMLANE_EXIT_MAIN" "specify a lane number: simlane metro ${sub:-logs} <N>"
    lane=$(simlane::registry_find_by_worktree "$(simlane::wt_toplevel)")
    [ -n "$lane" ] || simlane::die 1 "no lane is assigned to this worktree. Run 'simlane up' first"
  fi
  case "$sub" in
    logs) simlane::metro_logs "$lane" ;;
    restart)
      wt=$(simlane::registry_get "$lane" worktree)
      [ -d "$wt" ] || simlane::die 1 "worktree for lane $lane not found: $wt"
      main=$(simlane::registry_get "$lane" project)
      pj=$(cd "$wt" && simlane::project_config)
      simlane::metro_stop "$lane"
      simlane::metro_wait_free "$(simlane::metro_port "$lane")" 5 || true
      simlane::metro_launch "$lane" "$pj" "$wt" "$main" "--reset-cache"
      simlane::metro_wait_ready "$(simlane::metro_port "$lane")" "$(simlane::config_get .metroReadyTimeoutSec)" \
        || simlane::die "$SIMLANE_EXIT_METRO" "Metro did not become ready after the restart. Check 'simlane metro logs $lane'"
      simlane::log "Metro restarted (lane $lane)" ;;
    *) simlane::die 1 "usage: simlane metro logs|restart [N]" ;;
  esac
}
