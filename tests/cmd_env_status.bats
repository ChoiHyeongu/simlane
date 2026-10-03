#!/usr/bin/env bats
load test_helper
setup() {
  setup_env; source_libs; make_repo "$TD/repo"; WT=$(make_worktree "$TD/repo" feat-a)
  echo '[{"udid":"S1","name":"Simlane 1","state":"Booted"},{"udid":"P","name":"iPhone 16","state":"Booted"}]' > "$FAKE_STATE/devices.json"
}
alloc_wt() { simlane::registry_allocate "$WT" "$(simlane::dir_inode "$WT")" "$TD/repo" . com.example.app RCT_jsLocation >/dev/null; }

@test "env: on the main checkout only RESERVED is exported" {
  cd "$TD/repo"; run cmd_env
  [ "$status" -eq 0 ]
  [ "$output" = "export SIMLANE_RESERVED_UDIDS='S1'" ]
}

@test "env: a worktree without a lane exports the five lane variables as empty (clears stale env)" {
  cd "$WT"; run cmd_env
  [ "$status" -eq 0 ]
  assert_contains "$output" "export SIMLANE_LANE=''"; assert_contains "$output" "export SIMLANE_METRO_PORT=''"; assert_contains "$output" "export SIMLANE_SIM_UDID=''"
  assert_contains "$output" "export SIMLANE_BUNDLE_ID=''"; assert_contains "$output" "export SIMLANE_PROJECT=''"
  assert_contains "$output" "export SIMLANE_RESERVED_UDIDS='S1'"
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" = "6" ]
}

@test "env: a worktree with a lane exports six variables" {
  alloc_wt; cd "$WT"; run cmd_env
  [ "$status" -eq 0 ]
  assert_contains "$output" "export SIMLANE_LANE='1'"
  assert_contains "$output" "export SIMLANE_METRO_PORT='8091'"
  assert_contains "$output" "export SIMLANE_SIM_UDID='S1'"
  assert_contains "$output" "export SIMLANE_BUNDLE_ID='com.example.app'"
  assert_contains "$output" "export SIMLANE_PROJECT='$TD/repo'"
  assert_contains "$output" "export SIMLANE_RESERVED_UDIDS='S1'"
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" = "6" ]
}

@test "env --json: a valid JSON object" {
  alloc_wt; cd "$WT"
  [ "$(cmd_env --json | jq -r .SIMLANE_METRO_PORT)" = "8091" ]
  cd "$TD/repo"
  [ "$(cmd_env --json | jq -c 'keys')" = '["SIMLANE_RESERVED_UDIDS"]' ]
}

@test "env: outside git it still exits 0 with RESERVED only" {
  cd "$TD"; run cmd_env
  [ "$status" -eq 0 ]; [ "$output" = "export SIMLANE_RESERVED_UDIDS='S1'" ]
}

@test "status: maxLanes rows with the assigned lane's worktree and Metro state" {
  mkdir -p "$XDG_CONFIG_HOME/simlane"; echo '{"maxLanes":2}' > "$XDG_CONFIG_HOME/simlane/config.json"
  alloc_wt; touch "$FAKE_STATE/metro-8091"; touch "$FAKE_STATE/tmux-simlane-1"
  run cmd_status
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" = "3" ]
  assert_contains "${lines[1]}" "8091"; assert_contains "${lines[1]}" "Booted"; assert_contains "${lines[1]}" "running/tmux"; assert_contains "${lines[1]}" "$WT"
  assert_contains "${lines[2]}" "8092"; assert_contains "${lines[2]}" "free"
}
