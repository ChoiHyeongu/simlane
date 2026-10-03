#!/usr/bin/env bash
# mkdir-based locks. The owner pid is written inside the lock directory; a dead owner makes the lock stale.

simlane::lock_dir() { printf '%s/locks/%s\n' "$(simlane::config_dir)" "$1"; }

simlane::lock_acquire() {   # NAME [TIMEOUT_SEC=30]
  local name=$1 timeout=${2:-30} dir waited=0 pid
  dir=$(simlane::lock_dir "$name")
  while ! mkdir "$dir" 2>/dev/null; do
    pid=$(cat "$dir/pid" 2>/dev/null || true)
    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
      simlane::log "removed stale lock: $name (pid $pid is gone)"
      rm -rf "$dir"
      continue
    fi
    if [ "$waited" -ge "$timeout" ]; then
      simlane::die 1 "timed out waiting for lock: $name (held by pid ${pid:-unknown})"
    fi
    if [ "$waited" -eq 0 ] || [ $((waited % 10)) -eq 0 ]; then
      simlane::log "waiting for lock: $name (held by pid ${pid:-unknown}, ${waited}s elapsed, timeout ${timeout}s)"
    fi
    sleep 1
    waited=$((waited + 1))
  done
  printf '%s' "$$" > "$dir/pid"
}

simlane::lock_release() { rm -rf "$(simlane::lock_dir "$1")"; }
