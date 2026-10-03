#!/usr/bin/env bash
# simlane version — print the installed version (the VERSION file at the install root)

cmd_version() {
  local f="$SIMLANE_HOME/VERSION"
  [ -f "$f" ] || simlane::die 1 "VERSION file not found: $f"
  tr -d '[:space:]' < "$f"
  printf '\n'
}
