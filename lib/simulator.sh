#!/usr/bin/env bash
# xcrun simctl wrappers. simlane only ever creates, boots, shuts down or writes defaults on devices named "Simlane N".

simlane::sim_name() { printf 'Simlane %s\n' "$1"; }

simlane::sim_devices_json() { xcrun simctl list devices -j; }

simlane::sim_find_udid() {   # NAME → first available UDID | empty
  simlane::sim_devices_json | jq -r --arg n "$1" '[.devices[][] | select(.name == $n and (.isAvailable // true))] | .[0].udid // empty'
}

simlane::sim_count_named() { simlane::sim_devices_json | jq -r --arg n "$1" '[.devices[][] | select(.name == $n)] | length'; }

simlane::sim_state() { simlane::sim_devices_json | jq -r --arg u "$1" '[.devices[][] | select(.udid == $u)] | .[0].state // empty'; }

simlane::sim_resolve_devicetype() {   # "iPhone 17 Pro" → identifier
  xcrun simctl list devicetypes -j | jq -r --arg n "$1" '[.devicetypes[] | select(.name == $n)] | .[0].identifier // empty'
}

simlane::sim_resolve_runtime() {   # "latest" | "26.5" → identifier
  if [ "$1" = latest ]; then
    xcrun simctl list runtimes -j | jq -r '[.runtimes[] | select(.platform == "iOS" and .isAvailable)] | sort_by(.version | split(".") | map(tonumber)) | last | .identifier // empty'
  else
    xcrun simctl list runtimes -j | jq -r --arg v "$1" '[.runtimes[] | select(.platform == "iOS" and .isAvailable and .version == $v)] | .[0].identifier // empty'
  fi
}

simlane::sim_ensure() {   # LANE → UDID (creates the simulator on first use)
  local name udid dt rt n
  name=$(simlane::sim_name "$1")
  n=$(simlane::sim_count_named "$name")
  [ "$n" -gt 1 ] && simlane::log "warning: $n simulators are named '$name'; using the first one"
  udid=$(simlane::sim_find_udid "$name")
  if [ -z "$udid" ]; then
    dt=$(simlane::sim_resolve_devicetype "$(simlane::config_get .simulator.deviceType)")
    rt=$(simlane::sim_resolve_runtime "$(simlane::config_get .simulator.runtime)")
    [ -n "$dt" ] && [ -n "$rt" ] || simlane::die 1 "cannot create simulator: unresolved deviceType/runtime (deviceType='$dt' runtime='$rt'). Check ~/.config/simlane/config.json"
    udid=$(xcrun simctl create "$name" "$dt" "$rt") || simlane::die 1 "failed to create simulator: $name"
    simlane::log "created simulator: $name ($udid)"
  fi
  printf '%s\n' "$udid"
}

simlane::sim_boot() {   # UDID (no-op when already booted)
  if [ "$(simlane::sim_state "$1")" != Booted ]; then
    xcrun simctl boot "$1" >/dev/null 2>&1 || true
  fi
  xcrun simctl bootstatus "$1" -b >/dev/null 2>&1 || true
}

simlane::sim_shutdown() {   # UDID
  if [ "$(simlane::sim_state "$1")" = Booted ]; then
    xcrun simctl shutdown "$1" >/dev/null 2>&1 || true
  fi
}

simlane::sim_defaults_write() {   # UDID BUNDLEID KEY VALUE
  xcrun simctl spawn "$1" defaults write "$2" "$3" -string "$4"
}

simlane::sim_defaults_delete() {   # UDID BUNDLEID KEY (quiet when the key does not exist)
  xcrun simctl spawn "$1" defaults delete "$2" "$3" >/dev/null 2>&1 || true
}

simlane::sim_reserved_udids() {   # every "Simlane N" device, comma-separated
  simlane::sim_devices_json | jq -r '[.devices[][] | select(.name | test("^Simlane [0-9]+$")) | .udid] | join(",")'
}
