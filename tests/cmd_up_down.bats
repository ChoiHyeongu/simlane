#!/usr/bin/env bats
load test_helper
setup() { setup_env; source_libs; make_repo "$TD/repo"; WT=$(make_worktree "$TD/repo" feat-a); }
count() { local n; n=$(grep -c "$1" "$FAKE_STATE/calls.log" 2>/dev/null) || true; printf '%s\n' "${n:-0}"; }   # grep -c prints 0 and exits 1 on no match

@test "up: exits 2 on the main checkout" {
  cd "$TD/repo"; run "$SIMLANE" up
  [ "$status" -eq 2 ]; assert_contains "$output" "not in a worktree"
}

@test "up: in a worktree, lane 1 — simulator created+booted, symlink, Metro (watchFolders), bundle address, build, env output" {
  cd "$WT"; run "$SIMLANE" up
  [ "$status" -eq 0 ]
  [ "$(simlane::registry_get 1 worktree)" = "$WT" ]
  [ "$(simlane::sim_state FAKE-UDID-1)" = "Booted" ]
  [ "$(readlink "$WT/node_modules")" = "$TD/repo/node_modules" ]
  [ "$(cat "$FAKE_STATE/tmux-simlane-1")" = "fake-metro --port 8091 --watchFolders $TD/repo/node_modules" ]
  grep -q "^-c $WT$" "$FAKE_STATE/tmux-args.log"
  grep -q '^defaults write com.example.app RCT_jsLocation -string localhost:8091$' "$FAKE_STATE/defaults.log"
  grep -q "^fake-build --udid FAKE-UDID-1 cwd=$TD/repo lang=" "$FAKE_STATE/calls.log"
  assert_contains "$output" "export SIMLANE_LANE='1'"; assert_contains "$output" "export SIMLANE_METRO_PORT='8091'"; assert_contains "$output" "export SIMLANE_SIM_UDID='FAKE-UDID-1'"
}

@test "up: running twice creates the simulator and Metro once but builds again" {
  cd "$WT"; "$SIMLANE" up >/dev/null; run "$SIMLANE" up
  [ "$status" -eq 0 ]
  [ "$(count 'simctl create')" = "1" ]; [ "$(count 'tmux new-session')" = "1" ]; [ "$(count '^fake-build')" = "2" ]
  assert_contains "$output" "reusing Metro session"
}

@test "up --no-app: skips the build" {
  cd "$WT"; run "$SIMLANE" up --no-app
  [ "$status" -eq 0 ]; [ "$(count '^fake-build')" = "0" ]
  grep -q 'defaults write' "$FAKE_STATE/defaults.log"
}

@test "up: from a subdirectory of the worktree everything resolves to the worktree root" {
  mkdir -p "$WT/src/deep"; cd "$WT/src/deep"; run "$SIMLANE" up --no-app
  [ "$status" -eq 0 ]; [ -L "$WT/node_modules" ]; [ ! -e "$WT/src/deep/node_modules" ]
  grep -q "^-c $WT$" "$FAKE_STATE/tmux-args.log"
}

@test "up: a worktree path with a space" {
  WS=$(make_worktree "$TD/repo" "feat a"); cd "$WS"; run "$SIMLANE" up --no-app
  [ "$status" -eq 0 ]
  [ -L "$WS/node_modules" ]
  grep -q "^-c $WS$" "$FAKE_STATE/tmux-args.log"
  [ "$(simlane::registry_get 1 worktree)" = "$WS" ]
}

@test "up: a main checkout path with a space keeps watchFolders quoted" {
  make_repo "$TD/my repo"; W=$(make_worktree "$TD/my repo" feat-a); cd "$W"; run "$SIMLANE" up --no-app
  [ "$status" -eq 0 ]
  grep -qF -- "--watchFolders $TD/my\\ repo/node_modules" "$FAKE_STATE/tmux-simlane-1"
}

@test "up: exits 3 with the status table when all lanes are in use" {
  mkdir -p "$XDG_CONFIG_HOME/simlane"; echo '{"maxLanes":1}' > "$XDG_CONFIG_HOME/simlane/config.json"
  cd "$WT"; "$SIMLANE" up --no-app >/dev/null
  W2=$(make_worktree "$TD/repo" feat-b); cd "$W2"; run "$SIMLANE" up --no-app
  [ "$status" -eq 3 ]; assert_contains "$output" "all lanes are in use"; assert_contains "$output" "LANE"
}

@test "up: exits 5 without writing the address or building when a foreign process holds the port" {
  touch "$FAKE_STATE/listen-8091"; cd "$WT"; run "$SIMLANE" up
  [ "$status" -eq 5 ]; assert_contains "$output" "does not own"
  [ ! -f "$FAKE_STATE/defaults.log" ]; [ "$(count '^fake-build')" = "0" ]
}

@test "up: exits 4 without writing the address or building when Metro never becomes ready (8081 fallback guard)" {
  mkdir -p "$XDG_CONFIG_HOME/simlane"; echo '{"metroReadyTimeoutSec":1}' > "$XDG_CONFIG_HOME/simlane/config.json"
  export FAKE_METRO_NEVER_READY=1; cd "$WT"; run "$SIMLANE" up
  [ "$status" -eq 4 ]; assert_contains "$output" "not launching the app"
  [ ! -f "$FAKE_STATE/defaults.log" ]; [ "$(count '^fake-build')" = "0" ]
}

@test "up: a worktree recreated at the same path restarts Metro (inode changed)" {
  cd "$WT"; "$SIMLANE" up --no-app >/dev/null
  old=$(simlane::registry_get 1 inode)
  cd "$TD/repo"; git worktree remove --force "$WT"; WT=$(make_worktree "$TD/repo" feat-a)
  cd "$WT"; run "$SIMLANE" up --no-app
  [ "$status" -eq 0 ]; assert_contains "$output" "inode changed"
  [ "$(count 'tmux new-session')" = "2" ]; [ "$(simlane::registry_get 1 inode)" != "$old" ]
}

@test "up: variables listed in env are forwarded to tmux with -e" {
  echo '{"ios":{"scheme":"S","bundleId":"b","buildCommand":"fake-build"},"metro":{"startCommand":"fake-metro"},"env":["TOKEN_X"]}' > "$WT/.simlane.json"
  export TOKEN_X=secret; cd "$WT"; "$SIMLANE" up --no-app >/dev/null
  grep -q '^-e TOKEN_X=secret$' "$FAKE_STATE/tmux-args.log"
}

@test "up: a lane freed by a vanished worktree gets its stale Metro stopped before reuse" {
  cd "$WT"; "$SIMLANE" up --no-app >/dev/null
  rm -rf "$WT"
  W2=$(make_worktree "$TD/repo" feat-b); cd "$W2"; run "$SIMLANE" up --no-app
  [ "$status" -eq 0 ]; [ "$(simlane::registry_get 1 worktree)" = "$W2" ]
  [ "$(count 'tmux new-session')" = "2" ]; assert_contains "$output" "reclaimed"
}

@test "up: the inode update happens while holding the registry lock" {
  cd "$WT"; "$SIMLANE" up --no-app >/dev/null
  cd "$TD/repo"; git worktree remove --force "$WT"; WT=$(make_worktree "$TD/repo" feat-a); cd "$WT"
  eval "orig_registry_update() $(declare -f simlane::registry_update | sed '1d')"
  simlane::registry_update() { [ -d "$(simlane::lock_dir registry)" ] || echo UNLOCKED >> "$FAKE_STATE/locks.log"; orig_registry_update "$@"; }
  run cmd_up --no-app
  [ "$status" -eq 0 ]; [ ! -f "$FAKE_STATE/locks.log" ]
}

@test "prepare: only links dependencies; main checkout exits 2" {
  cd "$WT"; run "$SIMLANE" prepare
  [ "$status" -eq 0 ]; [ -L "$WT/node_modules" ]; [ "$(count 'xcrun')" = "0" ]; [ "$(count 'tmux')" = "0" ]
  cd "$TD/repo"; run "$SIMLANE" prepare; [ "$status" -eq 2 ]
}

@test "down: kills Metro, deletes the address, shuts the simulator down, releases the lane; running again is a quiet no-op" {
  cd "$WT"; "$SIMLANE" up --no-app >/dev/null; run "$SIMLANE" down
  [ "$status" -eq 0 ]
  [ ! -f "$FAKE_STATE/tmux-simlane-1" ]
  grep -q '^defaults delete com.example.app RCT_jsLocation$' "$FAKE_STATE/defaults.log"
  [ "$(simlane::sim_state FAKE-UDID-1)" = "Shutdown" ]
  [ -z "$(simlane::registry_get 1 worktree)" ]
  run "$SIMLANE" down; [ "$status" -eq 0 ]; assert_contains "$output" "no lane is assigned"
}

@test "down N / --all: other lanes are left alone" {
  cd "$WT"; "$SIMLANE" up --no-app >/dev/null
  W2=$(make_worktree "$TD/repo" feat-b); cd "$W2"; "$SIMLANE" up --no-app >/dev/null
  cd "$TD"; "$SIMLANE" down 1
  [ -z "$(simlane::registry_get 1 worktree)" ]; [ "$(simlane::registry_get 2 worktree)" = "$W2" ]; [ -f "$FAKE_STATE/tmux-simlane-2" ]
  "$SIMLANE" down --all
  [ -z "$(simlane::registry_get 2 worktree)" ]; [ ! -f "$FAKE_STATE/tmux-simlane-2" ]
}

@test "gc: reclaims vanished worktrees and kills orphan tmux sessions" {
  cd "$WT"; "$SIMLANE" up --no-app >/dev/null
  rm -rf "$WT"; touch "$FAKE_STATE/tmux-simlane-4"
  cd "$TD"; run "$SIMLANE" gc
  [ "$status" -eq 0 ]
  [ -z "$(simlane::registry_get 1 worktree)" ]; [ ! -f "$FAKE_STATE/tmux-simlane-1" ]; [ ! -f "$FAKE_STATE/tmux-simlane-4" ]
  [ "$(simlane::sim_state FAKE-UDID-1)" = "Shutdown" ]
}

@test "metro logs / restart" {
  cd "$WT"; "$SIMLANE" up --no-app >/dev/null
  run "$SIMLANE" metro logs; [ "$status" -eq 0 ]; assert_contains "$output" "fake metro log line"
  run "$SIMLANE" metro restart; [ "$status" -eq 0 ]
  [ "$(count 'tmux new-session')" = "2" ]; grep -q -- '--reset-cache' "$FAKE_STATE/tmux-simlane-1"
  cd "$TD/repo"; run "$SIMLANE" metro logs; [ "$status" -eq 2 ]
}

@test "metro restart: survives a port that lingers briefly after kill-session (no exit 5)" {
  cd "$WT"; "$SIMLANE" up --no-app >/dev/null
  export FAKE_METRO_LINGER_SEC=2
  run "$SIMLANE" metro restart; [ "$status" -eq 0 ]; [ "$(count 'tmux new-session')" = "2" ]
}
