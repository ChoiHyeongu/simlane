#!/usr/bin/env bats
load test_helper
setup() { setup_env; source_libs; }

@test "lock: acquire writes a pid file, release removes the directory" {
  simlane::lock_acquire t1 2
  d=$(simlane::lock_dir t1)
  [ -d "$d" ]; [ "$(cat "$d/pid")" = "$$" ]
  simlane::lock_release t1
  [ ! -d "$d" ]
}

@test "lock: a lock held by a live pid times out with exit 1 and reports the wait" {
  simlane::lock_acquire t2 2
  run simlane::lock_acquire t2 1
  [ "$status" -eq 1 ]
  assert_contains "$output" "waiting for lock"
  assert_contains "$output" "timed out waiting for lock"
  simlane::lock_release t2
}

@test "lock: a stale lock (dead pid) is removed and acquired" {
  d=$(simlane::lock_dir t3); mkdir -p "$d"; echo 999999 > "$d/pid"
  run simlane::lock_acquire t3 2
  [ "$status" -eq 0 ]
  assert_contains "$output" "stale"
}

@test "lock: a lock without a pid file (just created) is not stale — we wait" {
  d=$(simlane::lock_dir t4); mkdir -p "$d"
  run simlane::lock_acquire t4 1
  [ "$status" -eq 1 ]
  rm -rf "$d"
}
