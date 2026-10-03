#!/usr/bin/env bash
# Contributor install from a git clone: symlink ~/bin/simlane, then `simlane setup` (skill; pass --hooks for hooks).
# Users install with Homebrew instead (README). Idempotent.
set -euo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd -P)
mkdir -p "$HOME/bin"
ln -sfn "$HERE/bin/simlane" "$HOME/bin/simlane"
echo "installed: $HOME/bin/simlane → $HERE/bin/simlane"
"$HERE/bin/simlane" setup "$@"
case ":$PATH:" in
  *":$HOME/bin:"*) ;;
  *) echo "note: $HOME/bin is not on your PATH; add it in your shell rc" ;;
esac
