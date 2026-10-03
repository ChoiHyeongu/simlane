#!/usr/bin/env bash
# Register `simlane claude-hook` for SessionStart, CwdChanged and FileChanged in ~/.claude/settings.json.
# Idempotent per event, replaces stale claude-hook entries from older installs, and backs the file up before writing.
set -euo pipefail
F="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
CMD='[ -x "$HOME/bin/simlane" ] && "$HOME/bin/simlane" claude-hook || true'

mkdir -p "$(dirname "$F")"
[ -f "$F" ] || echo '{}' > "$F"
jq -e . "$F" >/dev/null 2>&1 || { echo "settings.json is not valid JSON: $F" >&2; exit 1; }

stale=$(jq --arg c "$CMD" '[.hooks // {} | .[]? | .[]? | .hooks[]? | .command | select(. != $c and test(" claude-hook"))] | length' "$F")
missing=$(jq --arg c "$CMD" '[("SessionStart","CwdChanged","FileChanged") as $ev | select(([.hooks[$ev][]? | .hooks[]? | .command] | index($c)) == null)] | length' "$F")
if [ "$stale" -eq 0 ] && [ "$missing" -eq 0 ]; then
  echo "already registered: $F"
  exit 0
fi

cp "$F" "$F.bak.$(date +%Y%m%d%H%M%S)"
tmp=$(mktemp)
jq --arg c "$CMD" '
  def group: {hooks: [{type: "command", command: $c}]};
  def drop_stale: map(.hooks |= map(select((.command | test(" claude-hook") | not) or .command == $c))) | map(select(.hooks | length > 0));
  def ensure: if ([.[]? | .hooks[]? | .command] | index($c)) == null then . + [group] else . end;
  .hooks = ((.hooks // {})
    | with_entries(.value |= (if type == "array" then drop_stale else . end))
    | .SessionStart = ((.SessionStart // []) | ensure)
    | .CwdChanged   = ((.CwdChanged   // []) | ensure)
    | .FileChanged  = ((.FileChanged  // []) | ensure))
' "$F" > "$tmp" && mv "$tmp" "$F"
[ "$stale" -gt 0 ] && echo "removed $stale stale claude-hook entr$([ "$stale" -eq 1 ] && echo y || echo ies)"
echo "registered: $F (backup: $F.bak.*)"
