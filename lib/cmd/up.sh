#!/usr/bin/env bash
# simlane up [--no-app] — the lane lifecycle. The order is the contract: Metro ready → bundle address → app
# (otherwise React Native silently falls back to port 8081).

simlane::metro_launch() {   # LANE PROJECT_JSON WT_ROOT MAIN_ROOT [EXTRA_FLAGS]
  local lane=$1 pj=$2 wt=$3 main=$4 extra=${5:-} port status appDir cwd cmd watch envs
  port=$(simlane::metro_port "$lane")
  status=$(simlane::metro_status "$port")
  [ "$status" = free ] || simlane::die "$SIMLANE_EXIT_PORT" "port $port is held by a process simlane does not own ($status). Check: lsof -nP -iTCP:$port -sTCP:LISTEN"
  appDir=$(jq -r .appDir <<<"$pj")
  cwd=$(cd "$wt/$appDir" && pwd -P)
  cmd="$(jq -r .metro.startCommand <<<"$pj") --port $port"
  if [ -z "$(jq -r '.deps.install // empty' <<<"$pj")" ]; then
    watch=$(cd "$main/$appDir/node_modules" 2>/dev/null && pwd -P) || simlane::die 1 "node_modules not found on the main checkout: $main/$appDir/node_modules"
    cmd="$cmd --watchFolders $(printf '%q' "$watch")"   # the command runs through a shell inside tmux; quote the path
  fi
  [ -n "$extra" ] && cmd="$cmd $extra"
  envs=$(jq -r '.env[]?' <<<"$pj")
  simlane::log "starting Metro: tmux $(simlane::metro_session "$lane") → $cmd"
  # shellcheck disable=SC2086  # the list of variable names is word-split on purpose
  simlane::metro_start "$lane" "$cwd" "$cmd" $envs
}

cmd_up() {   # [--no-app]
  local no_app=0
  [ "${1:-}" = --no-app ] && no_app=1
  simlane::wt_is_worktree || simlane::die "$SIMLANE_EXIT_MAIN" "not in a worktree: lanes exist only for git worktrees. On the main checkout use your repo's own scripts (e.g. yarn ios)"
  local wt main pj appDir bundleId key inode lane prev_inode udid port timeout rc=0 dead d du
  wt=$(simlane::wt_toplevel); main=$(simlane::wt_main_root); pj=$(simlane::project_config)
  appDir=$(jq -r .appDir <<<"$pj"); bundleId=$(jq -r .ios.bundleId <<<"$pj"); key=$(jq -r .ios.jsLocationKey <<<"$pj")
  inode=$(simlane::dir_inode "$wt")

  simlane::lock_acquire registry 30
  dead=$(simlane::registry_reclaim_dead)   # lanes whose worktree is gone; their Metro/simulator are cleaned up below, outside the lock
  if lane=$(simlane::registry_allocate "$wt" "$inode" "$main" "$appDir" "$bundleId" "$key"); then rc=0; else rc=$?; fi
  if [ "$rc" -ne 0 ]; then
    simlane::lock_release registry
    cmd_status >&2
    simlane::die "$SIMLANE_EXIT_EXHAUSTED" "all lanes are in use (maxLanes=$(simlane::config_get .maxLanes)). Run 'simlane down <N>' or raise maxLanes in config.json"
  fi
  prev_inode=$(simlane::registry_get "$lane" inode)
  simlane::lock_release registry
  for d in $dead; do
    simlane::metro_stop "$d"
    if [ "$d" != "$lane" ]; then
      du=$(simlane::sim_find_udid "$(simlane::sim_name "$d")" 2>/dev/null || true)
      [ -n "$du" ] && simlane::sim_shutdown "$du"
    fi
    simlane::log "reclaimed: lane $d (worktree directory gone) — stopped its stale Metro"
  done
  port=$(simlane::metro_port "$lane")

  udid=$(simlane::sim_ensure "$lane")
  simlane::sim_boot "$udid"
  simlane::deps_apply "$pj" "$wt" "$main"

  if [ "$prev_inode" != "$inode" ]; then
    simlane::log "worktree was recreated at the same path (inode changed) → restarting Metro"
    simlane::metro_stop "$lane"
    simlane::metro_wait_free "$port" 5 || true
    simlane::lock_acquire registry 30            # every registry write happens under the lock
    simlane::registry_update "$lane" inode "$inode"
    simlane::lock_release registry
  fi
  if simlane::metro_running "$lane"; then
    simlane::log "reusing Metro session: $(simlane::metro_session "$lane")"
  else
    simlane::metro_launch "$lane" "$pj" "$wt" "$main"
  fi
  timeout=$(simlane::config_get .metroReadyTimeoutSec)
  if ! simlane::metro_wait_ready "$port" "$timeout"; then
    simlane::metro_logs "$lane" 2>/dev/null | tail -n 30 >&2 || true
    simlane::die "$SIMLANE_EXIT_METRO" "Metro did not become ready within ${timeout}s; not launching the app (prevents the silent fallback to port 8081). Check 'simlane metro logs'"
  fi
  simlane::sim_defaults_write "$udid" "$bundleId" "$key" "localhost:$port"
  if [ "$no_app" -eq 0 ]; then simlane::app_build_install "$pj" "$main" "$udid"; fi
  simlane::log "lane $lane ready: Metro :$port, simulator $(simlane::sim_name "$lane") ($udid)"
  cmd_env
}
