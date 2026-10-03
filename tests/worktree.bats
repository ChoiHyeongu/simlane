#!/usr/bin/env bats
load test_helper
setup() { setup_env; source_libs; make_repo "$TD/repo"; WT=$(make_worktree "$TD/repo" feat-a); }

@test "wt_is_worktree: false on the main checkout, true in a worktree" {
  cd "$TD/repo"; assert_fails simlane::wt_is_worktree
  cd "$WT"; simlane::wt_is_worktree
}

@test "wt_main_root: returns the main checkout's real path from a worktree" {
  cd "$WT"
  [ "$(simlane::wt_main_root)" = "$TD/repo" ]
}

@test "wt_toplevel: resolves the worktree root from a subdirectory" {
  mkdir -p "$WT/src/deep"; cd "$WT/src/deep"
  [ "$(simlane::wt_toplevel)" = "$WT" ]
  simlane::wt_is_worktree
}

@test "project_config: defaults are filled in" {
  cd "$WT"; pj=$(simlane::project_config)
  [ "$(jq -r .appDir <<<"$pj")" = "." ]
  [ "$(jq -r .ios.jsLocationKey <<<"$pj")" = "RCT_jsLocation" ]
  [ "$(jq -r .metro.startCommand <<<"$pj")" = "fake-metro" ]
  [ "$(jq -r '.deps.link[0]' <<<"$pj")" = "node_modules" ]
  [ "$(jq -r '.env | length' <<<"$pj")" = "0" ]
}

@test "project_config: buildCommand defaults to run-ios with the scheme" {
  cd "$TD/repo"; echo '{"ios":{"scheme":"Foo","bundleId":"b"}}' > .simlane.json
  [ "$(simlane::project_config | jq -r .ios.buildCommand)" = "react-native run-ios --scheme Foo" ]
}

@test "project_config: deps.install replaces the default link strategy instead of merging with it" {
  cd "$TD/repo"; echo '{"ios":{"scheme":"Foo","bundleId":"b"},"deps":{"install":"pnpm install"}}' > .simlane.json
  pj=$(simlane::project_config)
  [ "$(jq -r '.deps.install' <<<"$pj")" = "pnpm install" ]
  [ "$(jq -r '.deps.link // "absent"' <<<"$pj")" = "absent" ]
}

@test "project_config: missing file / invalid JSON / missing required fields exit 1 with a reason" {
  cd "$TD/repo"; rm .simlane.json
  run simlane::project_config; [ "$status" -eq 1 ]; assert_contains "$output" "not found"
  echo '{oops' > .simlane.json
  run simlane::project_config; [ "$status" -eq 1 ]; assert_contains "$output" "not valid JSON"
  echo '{"ios":{"bundleId":"b"}}' > .simlane.json
  run simlane::project_config; [ "$status" -eq 1 ]; assert_contains "$output" "ios.scheme is required"
  echo '{"ios":{"scheme":"S"}}' > .simlane.json
  run simlane::project_config; [ "$status" -eq 1 ]; assert_contains "$output" "ios.bundleId is required"
}
