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
    simlane::die 1 "--hooks is not available yet"
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
