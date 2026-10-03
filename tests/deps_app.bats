#!/usr/bin/env bats
load test_helper
setup() { setup_env; source_libs; make_repo "$TD/repo"; WT=$(make_worktree "$TD/repo" feat-a); cd "$WT"; PJ=$(simlane::project_config); }

@test "deps link: symlinks node_modules from the main checkout; idempotent" {
  simlane::deps_apply "$PJ" "$WT" "$TD/repo"
  [ -L "$WT/node_modules" ]
  [ "$(readlink "$WT/node_modules")" = "$TD/repo/node_modules" ]
  simlane::deps_apply "$PJ" "$WT" "$TD/repo"
}

@test "deps link: refuses to replace a real directory (exit 1)" {
  mkdir -p "$WT/node_modules"
  run simlane::deps_apply "$PJ" "$WT" "$TD/repo"
  [ "$status" -eq 1 ]; assert_contains "$output" "refusing to link"
}

@test "deps link: a symlink pointing elsewhere exits 1; a missing source exits 1" {
  ln -s /tmp "$WT/node_modules"
  run simlane::deps_apply "$PJ" "$WT" "$TD/repo"
  [ "$status" -eq 1 ]; assert_contains "$output" "points elsewhere"
  rm "$WT/node_modules"; rm -rf "$TD/repo/node_modules"
  run simlane::deps_apply "$PJ" "$WT" "$TD/repo"
  [ "$status" -eq 1 ]; assert_contains "$output" "link source not found"
}

@test "deps install: runs install and after at the worktree root" {
  echo '{"ios":{"scheme":"S","bundleId":"b"},"deps":{"install":"touch installed.marker","after":"touch after.marker"}}' > "$WT/.simlane.json"
  PJ=$(simlane::project_config)
  simlane::deps_apply "$PJ" "$WT" "$TD/repo"
  [ -f "$WT/installed.marker" ]; [ -f "$WT/after.marker" ]
  [ ! -e "$WT/node_modules" ]
}

@test "app build: substitutes {udid}, runs in the main appDir, releases the lock" {
  simlane::app_build_install "$PJ" "$TD/repo" FAKE-UDID-1
  grep -q "^fake-build --udid FAKE-UDID-1 cwd=$TD/repo lang=" "$FAKE_STATE/calls.log"
  [ -z "$(ls "$XDG_CONFIG_HOME/simlane/locks")" ]
}

@test "app build: exports en_US.UTF-8 when LANG is unset (xcpretty locale pitfall), keeps an existing LANG" {
  unset LANG LC_ALL
  simlane::app_build_install "$PJ" "$TD/repo" U1
  grep -q 'lang=en_US.UTF-8$' "$FAKE_STATE/calls.log"
  export LANG=ko_KR.UTF-8
  simlane::app_build_install "$PJ" "$TD/repo" U2
  grep -q 'lang=ko_KR.UTF-8$' "$FAKE_STATE/calls.log"
}

@test "app build: without the placeholder it appends --udid and --no-packager" {
  PJ=$(jq '.ios.buildCommand = "fake-build"' <<<"$PJ")
  simlane::app_build_install "$PJ" "$TD/repo" U9
  grep -q '^fake-build --udid U9 --no-packager cwd=' "$FAKE_STATE/calls.log"
}

@test "app build: a failed build exits 1 and the lock is released" {
  export FAKE_BUILD_EXIT=3
  run simlane::app_build_install "$PJ" "$TD/repo" U1
  [ "$status" -eq 1 ]; assert_contains "$output" "app build failed (exit 3)"
  [ -z "$(ls "$XDG_CONFIG_HOME/simlane/locks")" ]
}
