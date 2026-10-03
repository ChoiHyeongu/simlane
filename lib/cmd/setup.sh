#!/usr/bin/env bash
# simlane setup — link the Claude Code skill; --hooks also registers `simlane claude-hook` in ~/.claude/settings.json.
# Paths come from simlane::stable_home so they survive `brew upgrade`.

cmd_setup() {
  local hooks=0 arg home
  for arg in "$@"; do
    case "$arg" in
      --hooks) hooks=1 ;;
      *) simlane::die 1 "unknown argument: $arg (usage: simlane setup [--hooks])" ;;
    esac
  done
  home=$(simlane::stable_home)
  simlane::setup_skill "$home"
  if [ "$hooks" -eq 1 ]; then
    simlane::setup_hooks "$home/bin/simlane"
  fi
}

simlane::setup_skill() {   # STABLE_HOME → link ~/.claude/skills/simlane to STABLE_HOME/skills/simlane
  local src="$1/skills/simlane" dst="$HOME/.claude/skills/simlane" old
  [ -d "$src" ] || simlane::die 1 "skill directory not found: $src"
  mkdir -p "$HOME/.claude/skills"
  if [ -L "$dst" ]; then
    old=$(readlink "$dst")
    if [ "$old" = "$src" ]; then
      simlane::log "skill already linked: $dst → $src"
      return 0
    fi
    ln -sfn "$src" "$dst"
    simlane::log "skill relinked: $dst → $src (was $old)"
    return 0
  fi
  if [ -e "$dst" ]; then
    simlane::die 1 "refusing to link: $dst is a real directory, not a symlink. Move it away and re-run."
  fi
  ln -s "$src" "$dst"
  simlane::log "skill linked: $dst → $src"
}

simlane::setup_hooks() {   # BIN → register `BIN claude-hook` for SessionStart, CwdChanged and FileChanged
  # Idempotent per event; replaces simlane entries pointing at another binary (e.g. the old ~/bin/simlane); keeps every
  # other hook, including other tools' claude-hook entries; backs the file up before writing.
  local f="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}" bin=$1 cmd re stale missing tmp
  cmd="[ -x \"$bin\" ] && \"$bin\" claude-hook || true"
  re='simlane"? claude-hook'
  mkdir -p "$(dirname "$f")"
  [ -f "$f" ] || echo '{}' > "$f"
  jq -e . "$f" >/dev/null 2>&1 || simlane::die 1 "settings.json is not valid JSON: $f"

  stale=$(jq --arg c "$cmd" --arg re "$re" \
    '[.hooks // {} | .[]? | .[]? | .hooks[]? | (.command // "") | select(. != $c and test($re))] | length' "$f")
  missing=$(jq --arg c "$cmd" \
    '[("SessionStart","CwdChanged","FileChanged") as $ev | select(([.hooks[$ev][]? | .hooks[]? | .command] | index($c)) == null)] | length' "$f")
  if [ "$stale" -eq 0 ] && [ "$missing" -eq 0 ]; then
    simlane::log "hooks already registered: $f"
    return 0
  fi

  cp "$f" "$f.bak.$(date +%Y%m%d%H%M%S)"
  tmp=$(mktemp)
  jq --arg c "$cmd" --arg re "$re" '
    def group: {hooks: [{type: "command", command: $c}]};
    def drop_stale: map(.hooks |= map(select(((.command // "") | test($re) | not) or .command == $c))) | map(select(.hooks | length > 0));
    def ensure: if ([.[]? | .hooks[]? | .command] | index($c)) == null then . + [group] else . end;
    .hooks = ((.hooks // {})
      | with_entries(.value |= (if type == "array" then drop_stale else . end))
      | .SessionStart = ((.SessionStart // []) | ensure)
      | .CwdChanged   = ((.CwdChanged   // []) | ensure)
      | .FileChanged  = ((.FileChanged  // []) | ensure))
  ' "$f" > "$tmp"
  cat "$tmp" > "$f"
  rm -f "$tmp"
  if [ "$stale" -gt 0 ]; then
    if [ "$stale" -eq 1 ]; then simlane::log "removed 1 stale simlane hook entry"
    else simlane::log "removed $stale stale simlane hook entries"; fi
  fi
  simlane::log "hooks registered: $f (backup: $f.bak.*)"
}
