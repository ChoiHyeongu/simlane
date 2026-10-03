#!/usr/bin/env bats
load test_helper
setup() { setup_env; source_libs; }

@test "config_get: defaults apply when no config file exists" {
  [ "$(simlane::config_get .maxLanes)" = "6" ]
  [ "$(simlane::config_get .portBase)" = "8090" ]
  [ "$(simlane::config_get .simulator.deviceType)" = "iPhone 17 Pro" ]
  [ "$(simlane::config_get .metroReadyTimeoutSec)" = "60" ]
}

@test "config_get: the user config is deep-merged over the defaults" {
  mkdir -p "$XDG_CONFIG_HOME/simlane"
  echo '{"maxLanes":2,"simulator":{"runtime":"18.2"}}' > "$XDG_CONFIG_HOME/simlane/config.json"
  [ "$(simlane::config_get .maxLanes)" = "2" ]
  [ "$(simlane::config_get .portBase)" = "8090" ]
  [ "$(simlane::config_get .simulator.deviceType)" = "iPhone 17 Pro" ]
  [ "$(simlane::config_get .simulator.runtime)" = "18.2" ]
}

@test "config_json: invalid JSON exits 1 and names the file" {
  mkdir -p "$XDG_CONFIG_HOME/simlane"; echo '{nope' > "$XDG_CONFIG_HOME/simlane/config.json"
  run simlane::config_json
  [ "$status" -eq 1 ]
  assert_contains "$output" "not valid JSON"
}

@test "die: exits with the given code and prefixes the message" {
  run simlane::die 4 "no metro"
  [ "$status" -eq 4 ]
  [ "$output" = "simlane: no metro" ]
}

@test "bin: help exits 0, an unknown subcommand exits 1" {
  run "$SIMLANE" help
  [ "$status" -eq 0 ]; assert_contains "$output" "up"
  run "$SIMLANE" nope
  [ "$status" -eq 1 ]
}

@test "bin: every script passes bash -n" {
  for f in "$SIMLANE" "$SIMLANE_ROOT"/lib/*.sh "$SIMLANE_ROOT"/lib/cmd/*.sh; do
    [ -f "$f" ] || continue   # skip unmatched glob literals
    bash -n "$f"
  done
}

@test "harness: the assert_* helpers fail the test when they should (bash 3.2 [[ ]] / ! pitfall)" {
  run assert_contains hello zzz;      [ "$status" -eq 1 ]
  run assert_fails true;              [ "$status" -eq 1 ]
  run assert_not_contains hello ell;  [ "$status" -eq 1 ]
  run assert_endswith hello lo;       [ "$status" -eq 0 ]
}

@test "stable_home: a Homebrew Cellar path maps to the version-independent opt path" {
  source_libs
  [ "$(simlane::stable_home /opt/homebrew/Cellar/simlane/0.2.0/libexec)" = "/opt/homebrew/opt/simlane/libexec" ]
  [ "$(simlane::stable_home /usr/local/Cellar/simlane/1.10.3_1/libexec)" = "/usr/local/opt/simlane/libexec" ]
}

@test "stable_home: a git clone path is returned unchanged, and SIMLANE_HOME is the default" {
  source_libs
  [ "$(simlane::stable_home /Users/x/.local/share/simlane)" = "/Users/x/.local/share/simlane" ]
  [ "$(simlane::stable_home /tmp/Cellar/other/1.0/libexec)" = "/tmp/Cellar/other/1.0/libexec" ]
  [ "$(SIMLANE_HOME=/a/Cellar/simlane/0.3.0/libexec simlane::stable_home)" = "/a/opt/simlane/libexec" ]
}
