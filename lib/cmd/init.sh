#!/usr/bin/env bash
# simlane init — write a .simlane.json skeleton at the repository root

cmd_init() {
  local top f
  top=$(simlane::wt_toplevel) || simlane::die 1 "not a git repository: $PWD"
  f="$top/.simlane.json"
  [ -f "$f" ] && simlane::die 1 "already exists: $f"
  cat > "$f" <<'JSON'
{
  "appDir": ".",
  "ios": {
    "scheme": "CHANGE_ME",
    "bundleId": "CHANGE_ME",
    "buildCommand": "yarn ios",
    "jsLocationKey": "RCT_jsLocation"
  },
  "metro": { "startCommand": "yarn start" },
  "deps": { "link": ["node_modules"] },
  "env": []
}
JSON
  simlane::log "created: $f"
  simlane::log "  fill in ios.scheme / ios.bundleId and commit it. Monorepo: set appDir and deps.install. App that reads a dedicated key: ios.jsLocationKey. Variables for the tmux Metro session: env"
}
