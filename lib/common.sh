#!/usr/bin/env bash
# Shared helpers: exit codes, logging, global config. bash 3.2 compatible. Sourced only (no set -e here).
# shellcheck disable=SC2034  # the SIMLANE_EXIT_* codes are used by the files that source this one

SIMLANE_EXIT_MAIN=2        # running on the main checkout (no lane there)
SIMLANE_EXIT_EXHAUSTED=3   # all lanes in use
SIMLANE_EXIT_METRO=4       # Metro did not become ready
SIMLANE_EXIT_PORT=5        # lane port held by a process simlane does not own

simlane::log() { printf 'simlane: %s\n' "$*" >&2; }

simlane::die() {   # CODE MESSAGE…
  local code=$1; shift
  printf 'simlane: %s\n' "$*" >&2
  exit "$code"
}

simlane::require_cmd() {
  command -v "$1" >/dev/null 2>&1 || simlane::die 1 "required command not found: $1"
}

simlane::config_dir() {
  local d="${XDG_CONFIG_HOME:-$HOME/.config}/simlane"
  mkdir -p "$d/locks"
  printf '%s\n' "$d"
}

SIMLANE_CONFIG_DEFAULTS='{"maxLanes":6,"portBase":8090,"simulator":{"deviceType":"iPhone 17 Pro","runtime":"latest"},"metroReadyTimeoutSec":60}'

simlane::config_json() {   # defaults deep-merged with ~/.config/simlane/config.json
  local f
  f="$(simlane::config_dir)/config.json"
  if [ -f "$f" ]; then
    jq -e . "$f" >/dev/null 2>&1 || simlane::die 1 "config file is not valid JSON: $f"
    jq -s '.[0] * .[1]' <(printf '%s' "$SIMLANE_CONFIG_DEFAULTS") "$f"
  else
    printf '%s\n' "$SIMLANE_CONFIG_DEFAULTS"
  fi
}

simlane::config_get() {   # JQ_PATH → raw value
  simlane::config_json | jq -r "$1"
}

simlane::stable_home() {   # [PATH] → the install root that outside files (skill link, hook command) may point at
  # Homebrew resolves bin/simlane to <prefix>/Cellar/simlane/<version>/libexec, which `brew cleanup` deletes after an
  # upgrade; <prefix>/opt/simlane always points at the current version. No `brew` call: hooks run on every event.
  local h=${1:-$SIMLANE_HOME}
  case "$h" in
    */Cellar/simlane/*/libexec) printf '%s/opt/simlane/libexec\n' "${h%%/Cellar/simlane/*}" ;;
    *) printf '%s\n' "$h" ;;
  esac
}
