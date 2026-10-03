#!/usr/bin/env bash
# Worktree detection and per-repo configuration (.simlane.json).

simlane::wt_toplevel() { git rev-parse --show-toplevel 2>/dev/null; }

simlane::wt_is_worktree() {   # 0 inside a linked worktree; 1 on the main checkout or outside git
  local gd cd
  gd=$(git rev-parse --path-format=absolute --git-dir 2>/dev/null) || return 1
  cd=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  [ "$gd" != "$cd" ]
}

simlane::wt_main_root() {   # real path of the main checkout
  local cd
  cd=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  (cd "$cd/.." && pwd -P)
}

SIMLANE_PROJECT_DEFAULTS='{"appDir":".","ios":{"buildCommand":"","jsLocationKey":"RCT_jsLocation"},"metro":{"startCommand":"react-native start"},"deps":{"link":["node_modules"]},"env":[]}'

simlane::project_config() {   # → validated JSON with defaults applied
  local top f merged err
  top=$(simlane::wt_toplevel) || simlane::die 1 "not a git repository: $PWD"
  f="$top/.simlane.json"
  [ -f "$f" ] || simlane::die 1 ".simlane.json not found: $f (create one with 'simlane init')"
  jq -e . "$f" >/dev/null 2>&1 || simlane::die 1 ".simlane.json is not valid JSON: $f"
  if ! merged=$(jq -s '
      (.[1].deps) as $deps
      | (.[0] * .[1])
      | if $deps != null then .deps = $deps else . end
      | if (.ios.scheme // "") == "" then error("ios.scheme is required") else . end
      | if (.ios.bundleId // "") == "" then error("ios.bundleId is required") else . end
      | if .ios.buildCommand == "" then .ios.buildCommand = "react-native run-ios --scheme \(.ios.scheme)" else . end
    ' <(printf '%s' "$SIMLANE_PROJECT_DEFAULTS") "$f" 2>&1); then
    err=$(printf '%s' "$merged" | sed 's/^jq: error (at [^)]*): //')
    simlane::die 1 ".simlane.json validation failed: $err ($f)"
  fi
  printf '%s\n' "$merged"
}
