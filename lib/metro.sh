#!/usr/bin/env bash
# Metro lives in a tmux session named simlane-N. Readiness is probed like the RN CLI does: GET /status → packager-status:running.

simlane::metro_session() { printf 'simlane-%s\n' "$1"; }

# tmux -t matches by prefix (simlane-1 would match simlane-10), so targets always carry the "=" exact-match prefix.
simlane::metro_target() { printf '=%s\n' "$(simlane::metro_session "$1")"; }

simlane::metro_port() { printf '%s\n' "$(( $(simlane::config_get .portBase) + $1 ))"; }

simlane::metro_status() {   # PORT → running | other | free
  if curl -fsS --max-time 2 "http://localhost:$1/status" 2>/dev/null | grep -q 'packager-status:running'; then
    printf 'running\n'; return 0
  fi
  if lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1; then printf 'other\n'; else printf 'free\n'; fi
}

simlane::metro_running() { tmux has-session -t "$(simlane::metro_target "$1")" 2>/dev/null; }

simlane::metro_start() {   # LANE CWD CMD [ENV_NAME…] — only variables that are set are forwarded with -e (tmux sessions inherit the server's environment)
  local lane=$1 cwd=$2 cmd=$3 v
  shift 3
  local args=()
  for v in "$@"; do
    if [ -n "${!v:-}" ]; then args+=(-e "$v=${!v}"); fi
  done
  tmux new-session -d -s "$(simlane::metro_session "$lane")" -c "$cwd" ${args[@]+"${args[@]}"} "$cmd"
}

simlane::metro_wait_ready() {   # PORT TIMEOUT_SEC → 0 ready | 1 timed out
  local waited=0
  while [ "$waited" -lt "$2" ]; do
    [ "$(simlane::metro_status "$1")" = running ] && return 0
    sleep 1
    waited=$((waited + 1))
  done
  [ "$(simlane::metro_status "$1")" = running ]
}

simlane::metro_stop() { tmux kill-session -t "$(simlane::metro_target "$1")" 2>/dev/null || true; }

simlane::metro_wait_free() {   # PORT [TIMEOUT_SEC=5] → 0 free | 1 still held (kill-session is asynchronous; the port lingers briefly)
  local waited=0 timeout=${2:-5}
  while [ "$waited" -lt "$timeout" ]; do
    [ "$(simlane::metro_status "$1")" = free ] && return 0
    sleep 1
    waited=$((waited + 1))
  done
  [ "$(simlane::metro_status "$1")" = free ]
}

simlane::metro_logs() { tmux capture-pane -p -t "$(simlane::metro_target "$1")" -S -200; }
