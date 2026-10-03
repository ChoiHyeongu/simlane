#!/usr/bin/env bash
# Dependency strategies.
#   link:    symlink directories from the main checkout into the worktree (no install, never run install there).
#   install: run an install command (+ optional "after") at the worktree root (pnpm monorepos, etc.).

simlane::deps_apply() {   # PROJECT_JSON WT_ROOT MAIN_ROOT
  local pj=$1 wt=$2 main=$3 appDir install after p src dst srcdir
  appDir=$(jq -r .appDir <<<"$pj")
  install=$(jq -r '.deps.install // empty' <<<"$pj")
  if [ -n "$install" ]; then
    simlane::log "installing dependencies: $install (cwd: $wt)"
    (cd "$wt" && eval "$install") || simlane::die 1 "dependency install failed: $install"
    after=$(jq -r '.deps.after // empty' <<<"$pj")
    if [ -n "$after" ]; then
      simlane::log "deps.after: $after"
      (cd "$wt" && eval "$after") || simlane::die 1 "deps.after failed: $after"
    fi
    return 0
  fi
  srcdir=$(cd "$main/$appDir" 2>/dev/null && pwd -P) || simlane::die 1 "main appDir not found: $main/$appDir"
  for p in $(jq -r '.deps.link[]?' <<<"$pj"); do
    src="$srcdir/$p"
    dst="$wt/$appDir/$p"
    [ -e "$src" ] || simlane::die 1 "link source not found: $src (install dependencies on the main checkout first)"
    if [ -L "$dst" ]; then
      [ "$(readlink "$dst")" = "$src" ] || simlane::die 1 "symlink points elsewhere: $dst → $(readlink "$dst")"
    elif [ -e "$dst" ]; then
      simlane::die 1 "refusing to link: a real directory already exists at $dst (would shadow its dependencies)"
    else
      ln -s "$src" "$dst"
      simlane::log "linked: $dst → $src  (never run install in this worktree — it would overwrite the main checkout)"
    fi
  done
}
