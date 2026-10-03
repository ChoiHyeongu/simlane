#!/usr/bin/env bats
load test_helper
setup() { setup_env; source_libs; mkdir -p "$TD/wt"; }

@test "metro_port: portBase + N" {
  [ "$(simlane::metro_port 3)" = "8093" ]
  mkdir -p "$XDG_CONFIG_HOME/simlane"; echo '{"portBase":9000}' > "$XDG_CONFIG_HOME/simlane/config.json"
  [ "$(simlane::metro_port 1)" = "9001" ]
}

@test "metro_status: free / running / other" {
  [ "$(simlane::metro_status 8091)" = "free" ]
  touch "$FAKE_STATE/metro-8091"; [ "$(simlane::metro_status 8091)" = "running" ]
  touch "$FAKE_STATE/listen-8092"; [ "$(simlane::metro_status 8092)" = "other" ]
}

@test "metro_start: passes cwd, the command and only the variables that are set to tmux" {
  export FOO=bar; unset NOPE
  simlane::metro_start 1 "$TD/wt" "fake-metro --port 8091" FOO NOPE
  [ "$(cat "$FAKE_STATE/tmux-simlane-1")" = "fake-metro --port 8091" ]
  grep -q "^-c $TD/wt$" "$FAKE_STATE/tmux-args.log"
  grep -q '^-e FOO=bar$' "$FAKE_STATE/tmux-args.log"
  assert_fails grep -q 'NOPE' "$FAKE_STATE/tmux-args.log"
  simlane::metro_running 1
}

@test "metro_start: works with an empty variable list (bash 3.2 empty array)" {
  simlane::metro_start 2 "$TD/wt" "fake-metro --port 8092"
  simlane::metro_running 2
}

@test "metro_wait_ready: 0 once ready, 1 on timeout" {
  simlane::metro_start 1 "$TD/wt" "fake-metro --port 8091"
  simlane::metro_wait_ready 8091 2
  export FAKE_METRO_NEVER_READY=1
  simlane::metro_start 2 "$TD/wt" "fake-metro --port 8092"
  assert_fails simlane::metro_wait_ready 8092 1
}

@test "metro_stop: the session and its Metro go away; stopping a missing session is quiet" {
  simlane::metro_start 1 "$TD/wt" "fake-metro --port 8091"
  simlane::metro_stop 1
  assert_fails simlane::metro_running 1
  [ "$(simlane::metro_status 8091)" = "free" ]
  simlane::metro_stop 5
}

@test "metro_logs: capture-pane output" {
  simlane::metro_start 1 "$TD/wt" "fake-metro --port 8091"
  [ "$(simlane::metro_logs 1)" = "fake metro log line" ]
}

@test "metro_running/stop: no prefix matching — simlane-1 neither sees nor kills simlane-10" {
  simlane::metro_start 10 "$TD/wt" "fake-metro --port 8100"
  assert_fails simlane::metro_running 1
  simlane::metro_stop 1
  simlane::metro_running 10
  [ "$(simlane::metro_status 8100)" = "running" ]
}

@test "metro_wait_free: waits for a Metro that lingers briefly after kill-session" {
  simlane::metro_start 1 "$TD/wt" "fake-metro --port 8091"
  export FAKE_METRO_LINGER_SEC=2
  simlane::metro_stop 1
  [ "$(simlane::metro_status 8091)" = "running" ]
  simlane::metro_wait_free 8091 5
  [ "$(simlane::metro_status 8091)" = "free" ]
}
