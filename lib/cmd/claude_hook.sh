#!/usr/bin/env bash
# simlane claude-hook — Claude Code hook entry point shared by SessionStart, CwdChanged and FileChanged. Always exits 0.
# Reads the hook JSON ({cwd, hook_event_name, …}) on stdin, appends `simlane env` for that cwd to CLAUDE_ENV_FILE and
# returns watchPaths so Claude Code re-runs the hook whenever the lane registry changes.

cmd_claude_hook() {
  local input cwd event reg
  input=$(cat 2>/dev/null || true)
  cwd=$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null || true)
  event=$(jq -r '.hook_event_name // empty' <<<"$input" 2>/dev/null || true)
  reg=$(simlane::registry_path)
  if [ -n "${CLAUDE_ENV_FILE:-}" ] && [ -n "$cwd" ] && [ -d "$cwd" ]; then
    (cd "$cwd" && cmd_env) >> "$CLAUDE_ENV_FILE" 2>/dev/null || true
  fi
  case "$event" in
    # All three events need the hookSpecificOutput form; a top-level {"watchPaths"} is ignored and the watch is dropped.
    SessionStart|CwdChanged|FileChanged) jq -cn --arg e "$event" --arg p "$reg" '{hookSpecificOutput:{hookEventName:$e,watchPaths:[$p]}}' ;;
    *) : ;;
  esac
  return 0
}
