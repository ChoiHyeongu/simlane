#!/usr/bin/env bats
load test_helper
setup() { setup_env; source_libs; }

@test "sim_ensure: creates the simulator with the configured device type and the newest iOS runtime, then reuses it" {
  [ "$(simlane::sim_ensure 1)" = "FAKE-UDID-1" ]
  grep -q 'create Simlane 1 com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro com.apple.CoreSimulator.SimRuntime.iOS-26-5' "$FAKE_STATE/calls.log"
  [ "$(simlane::sim_ensure 1)" = "FAKE-UDID-1" ]
  [ "$(grep -c 'simctl create' "$FAKE_STATE/calls.log")" = "1" ]
}

@test "sim_ensure: a runtime version in the config selects that runtime" {
  mkdir -p "$XDG_CONFIG_HOME/simlane"; echo '{"simulator":{"runtime":"18.2"}}' > "$XDG_CONFIG_HOME/simlane/config.json"
  simlane::sim_ensure 2 >/dev/null
  grep -q 'create Simlane 2 .* com.apple.CoreSimulator.SimRuntime.iOS-18-2' "$FAKE_STATE/calls.log"
}

@test "sim_ensure: an unknown device type exits 1" {
  mkdir -p "$XDG_CONFIG_HOME/simlane"; echo '{"simulator":{"deviceType":"iPhone 99"}}' > "$XDG_CONFIG_HOME/simlane/config.json"
  run simlane::sim_ensure 1
  [ "$status" -eq 1 ]; assert_contains "$output" "cannot create simulator"
}

@test "sim_ensure: two simulators with the same name → warning, first one wins" {
  echo '[{"udid":"A","name":"Simlane 3","state":"Shutdown"},{"udid":"B","name":"Simlane 3","state":"Shutdown"}]' > "$FAKE_STATE/devices.json"
  run simlane::sim_ensure 3
  [ "$status" -eq 0 ]
  assert_contains "$output" "2 simulators"
  assert_endswith "$output" "A"
}

@test "sim_boot/shutdown: change state; boot is not sent again when already booted" {
  u=$(simlane::sim_ensure 1)
  simlane::sim_boot "$u"; [ "$(simlane::sim_state "$u")" = "Booted" ]
  simlane::sim_boot "$u"
  [ "$(grep -c "simctl boot $u" "$FAKE_STATE/calls.log")" = "1" ]
  simlane::sim_shutdown "$u"; [ "$(simlane::sim_state "$u")" = "Shutdown" ]
}

@test "sim_defaults_write/delete: go through simctl spawn defaults" {
  simlane::sim_defaults_write U1 com.example.app SimlaneJsLocation localhost:8091
  simlane::sim_defaults_delete U1 com.example.app SimlaneJsLocation
  grep -q '^defaults write com.example.app SimlaneJsLocation -string localhost:8091$' "$FAKE_STATE/defaults.log"
  grep -q '^defaults delete com.example.app SimlaneJsLocation$' "$FAKE_STATE/defaults.log"
}

@test "sim_reserved_udids: only devices named 'Simlane N', comma-separated" {
  echo '[{"udid":"S1","name":"Simlane 1","state":"Booted"},{"udid":"P","name":"iPhone 16","state":"Booted"},{"udid":"S2","name":"Simlane 2","state":"Shutdown"},{"udid":"X","name":"Simlane Spike","state":"Shutdown"}]' > "$FAKE_STATE/devices.json"
  [ "$(simlane::sim_reserved_udids)" = "S1,S2" ]
}
