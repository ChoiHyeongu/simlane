#!/usr/bin/env bats
load test_helper
setup() {
  setup_env; source_libs; make_repo "$TD/repo"; WT=$(make_worktree "$TD/repo" feat-a)
  echo '[{"udid":"S1","name":"Simlane 1","state":"Booted"}]' > "$FAKE_STATE/devices.json"
  REG=$(simlane::registry_path); export ENVF="$TD/envfile"
}
hook() { printf '{"cwd":"%s","hook_event_name":"%s","session_id":"x"}' "$1" "$2" | "$SIMLANE" claude-hook; }

@test "init: writes the skeleton; a second run exits 1" {
  mkdir -p "$TD/fresh"; ( cd "$TD/fresh" && git init -q -b main . )
  cd "$TD/fresh"; run "$SIMLANE" init
  [ "$status" -eq 0 ]; jq -e . .simlane.json >/dev/null
  [ "$(jq -r .ios.scheme .simlane.json)" = "CHANGE_ME" ]; [ "$(jq -r '.deps.link[0]' .simlane.json)" = "node_modules" ]
  run "$SIMLANE" init; [ "$status" -eq 1 ]; assert_contains "$output" "already exists"
}

@test "claude-hook SessionStart: appends the lane env to the env file and returns hookSpecificOutput.watchPaths" {
  simlane::registry_allocate "$WT" "$(simlane::dir_inode "$WT")" "$TD/repo" . com.example.app RCT_jsLocation >/dev/null
  echo "export KEEP=1" > "$ENVF"
  CLAUDE_ENV_FILE="$ENVF" run hook "$WT" SessionStart
  [ "$status" -eq 0 ]
  [ "$output" = "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"watchPaths\":[\"$REG\"]}}" ]
  grep -q '^export KEEP=1$' "$ENVF"; grep -q "^export SIMLANE_LANE='1'$" "$ENVF"; grep -q "^export SIMLANE_METRO_PORT='8091'$" "$ENVF"
}

@test "claude-hook CwdChanged/FileChanged: hookSpecificOutput watchPaths (a top-level watchPaths is ignored by Claude Code)" {
  CLAUDE_ENV_FILE="$ENVF" run hook "$TD/repo" CwdChanged
  [ "$output" = "{\"hookSpecificOutput\":{\"hookEventName\":\"CwdChanged\",\"watchPaths\":[\"$REG\"]}}" ]
  CLAUDE_ENV_FILE="$ENVF" run hook "$TD/repo" FileChanged
  [ "$output" = "{\"hookSpecificOutput\":{\"hookEventName\":\"FileChanged\",\"watchPaths\":[\"$REG\"]}}" ]
  [ "$(grep -c SIMLANE_RESERVED_UDIDS "$ENVF")" = "2" ]
}

@test "claude-hook: outside git only RESERVED is written; a missing cwd writes nothing" {
  CLAUDE_ENV_FILE="$ENVF" run hook "$TD" SessionStart
  [ "$status" -eq 0 ]; [ "$(cat "$ENVF")" = "export SIMLANE_RESERVED_UDIDS='S1'" ]
  rm -f "$ENVF"
  CLAUDE_ENV_FILE="$ENVF" run hook "$TD/nope" SessionStart
  [ "$status" -eq 0 ]; [ ! -f "$ENVF" ]; assert_contains "$output" watchPaths
}

@test "claude-hook: no CLAUDE_ENV_FILE / unknown event / empty stdin all exit 0" {
  unset CLAUDE_ENV_FILE
  run hook "$WT" SessionStart; [ "$status" -eq 0 ]; [ ! -f "$ENVF" ]
  run hook "$WT" Stop; [ "$status" -eq 0 ]; [ -z "$output" ]
  run bash -c "printf '' | '$SIMLANE' claude-hook"; [ "$status" -eq 0 ]
}
