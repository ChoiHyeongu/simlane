#!/usr/bin/env bash
# simlane gc — reclaim lanes whose worktree directory is gone (Metro, simulator, registry) and kill orphan simlane-N tmux sessions.

cmd_gc() {
  local s udid dead sessions name
  simlane::lock_acquire registry 30
  dead=$(simlane::registry_reclaim_dead)
  simlane::lock_release registry
  for s in $dead; do
    simlane::metro_stop "$s"
    udid=$(simlane::sim_find_udid "$(simlane::sim_name "$s")" 2>/dev/null || true)
    [ -n "$udid" ] && simlane::sim_shutdown "$udid"
    simlane::log "reclaimed: lane $s (worktree directory gone)"
  done
  sessions=$(tmux ls -F '#S' 2>/dev/null | grep -E '^simlane-[0-9]+$' || true)
  for name in $sessions; do
    s=${name#simlane-}
    if [ -z "$(simlane::registry_get "$s" worktree)" ]; then
      tmux kill-session -t "=$name" 2>/dev/null || true
      simlane::log "reclaimed: orphan Metro session $name"
    fi
  done
  simlane::log "gc done"
}
