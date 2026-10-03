#!/usr/bin/env bash
# simlane prepare — apply the dependency strategy only. No simulator, no Metro.

cmd_prepare() {
  simlane::wt_is_worktree || simlane::die "$SIMLANE_EXIT_MAIN" "not in a worktree: prepare is only needed inside a git worktree"
  local wt main pj
  wt=$(simlane::wt_toplevel); main=$(simlane::wt_main_root); pj=$(simlane::project_config)
  simlane::deps_apply "$pj" "$wt" "$main"
  simlane::log "prepare done: $wt"
}
