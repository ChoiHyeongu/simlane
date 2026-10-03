#!/usr/bin/env bats
load test_helper
setup() { setup_env; source_libs; mkdir -p "$TD/wt1" "$TD/wt2" "$TD/wt3"; }

alloc() { simlane::registry_allocate "$1" "$(simlane::dir_inode "$1")" "$TD/repo" . com.example.app RCT_jsLocation; }

@test "registry_read: creates an empty registry on first read" {
  [ "$(simlane::registry_read | jq -c .)" = '{"version":1,"lanes":{}}' ]
  [ -f "$(simlane::registry_path)" ]
}

@test "allocate: first worktree gets lane 1, the same worktree keeps it, another worktree gets the next free lane" {
  [ "$(alloc "$TD/wt1")" = "1" ]
  [ "$(alloc "$TD/wt1")" = "1" ]
  [ "$(alloc "$TD/wt2")" = "2" ]
  [ "$(simlane::registry_get 2 bundleId)" = "com.example.app" ]
  [ "$(simlane::registry_get 2 jsLocationKey)" = "RCT_jsLocation" ]
  [ "$(simlane::registry_get 1 inode)" = "$(simlane::dir_inode "$TD/wt1")" ]
}

@test "allocate: a released low lane is reused" {
  alloc "$TD/wt1" >/dev/null; alloc "$TD/wt2" >/dev/null
  simlane::registry_release 1
  [ "$(alloc "$TD/wt3")" = "1" ]
  [ "$(simlane::registry_lanes | tr '\n' ' ')" = "1 2 " ]
}

@test "allocate: returns 3 when maxLanes is exhausted" {
  mkdir -p "$XDG_CONFIG_HOME/simlane"; echo '{"maxLanes":1}' > "$XDG_CONFIG_HOME/simlane/config.json"
  alloc "$TD/wt1" >/dev/null
  run alloc "$TD/wt2"
  [ "$status" -eq 3 ]
}

@test "reclaim_dead: releases lanes whose worktree directory is gone and prints them" {
  alloc "$TD/wt1" >/dev/null; alloc "$TD/wt2" >/dev/null
  rmdir "$TD/wt1"
  [ "$(simlane::registry_reclaim_dead)" = "1" ]
  [ -z "$(simlane::registry_get 1 worktree)" ]
  [ "$(simlane::registry_get 2 worktree)" = "$TD/wt2" ]
}

@test "allocate: reclaims dead lanes before reporting exhaustion" {
  mkdir -p "$XDG_CONFIG_HOME/simlane"; echo '{"maxLanes":1}' > "$XDG_CONFIG_HOME/simlane/config.json"
  alloc "$TD/wt1" >/dev/null; rmdir "$TD/wt1"
  [ "$(alloc "$TD/wt2")" = "1" ]
}

@test "update/write: the file stays valid JSON after a field update" {
  alloc "$TD/wt1" >/dev/null
  simlane::registry_update 1 inode 42
  [ "$(simlane::registry_get 1 inode)" = "42" ]
  jq -e . "$(simlane::registry_path)" >/dev/null
}
