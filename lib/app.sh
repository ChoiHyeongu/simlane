#!/usr/bin/env bash
# The app is built and installed from the main checkout's appDir (one DerivedData, incremental builds). This is a deliberate
# exception to worktree isolation — see docs/design.md.

simlane::app_build_install() {   # PROJECT_JSON MAIN_ROOT UDID
  local pj=$1 main=$2 udid=$3 appDir cmd dir hash rc=0
  appDir=$(jq -r .appDir <<<"$pj")
  cmd=$(jq -r .ios.buildCommand <<<"$pj")
  case "$cmd" in
    *'{udid}'*) cmd=${cmd//\{udid\}/$udid} ;;
    *)          cmd="$cmd --udid $udid --no-packager" ;;
  esac
  dir=$(cd "$main/$appDir" 2>/dev/null && pwd -P) || simlane::die 1 "main appDir not found: $main/$appDir"
  hash=$(printf '%s' "$dir" | shasum | cut -c1-12)
  # Non-interactive shells (hooks, tmux) often have no locale; xcpretty then crashes on non-ASCII build output.
  [ -n "${LANG:-}" ] || export LANG=en_US.UTF-8
  [ -n "${LC_ALL:-}" ] || export LC_ALL="$LANG"
  simlane::lock_acquire "build-$hash" 1800
  simlane::log "building and installing the app (in the main checkout, by design): $cmd"
  simlane::log "  cwd: $dir"
  if (cd "$dir" && eval "$cmd"); then rc=0; else rc=$?; fi
  simlane::lock_release "build-$hash"
  [ "$rc" -eq 0 ] || simlane::die 1 "app build failed (exit $rc)"
}
