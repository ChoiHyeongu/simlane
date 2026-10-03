#!/usr/bin/env bash
# Install simlane: symlink ~/bin/simlane and the Claude Code skill. Idempotent.
set -euo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd -P)
mkdir -p "$HOME/bin" "$HOME/.claude/skills"
ln -sfn "$HERE/bin/simlane" "$HOME/bin/simlane"
echo "installed: $HOME/bin/simlane → $HERE/bin/simlane"
if [ -d "$HERE/skills/simlane" ]; then
  target="$HOME/.claude/skills/simlane"
  if [ -d "$target" ] && [ ! -L "$target" ]; then
    echo "refusing to link: $target is a real directory, not a symlink. Move it away and re-run." >&2
    exit 1
  fi
  ln -sfn "$HERE/skills/simlane" "$target"
  echo "installed: $target → $HERE/skills/simlane"
fi
case ":$PATH:" in
  *":$HOME/bin:"*) ;;
  *) echo "note: $HOME/bin is not on your PATH; add it in your shell rc" ;;
esac
