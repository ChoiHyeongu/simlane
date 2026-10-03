# Shared bats helpers. Every .bats file does `load test_helper` and calls setup_env from setup().
SIMLANE_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
SIMLANE="$SIMLANE_ROOT/bin/simlane"

setup_env() {
  TD="$(cd "$BATS_TEST_TMPDIR" && pwd -P)"   # resolve /private/var/… so real-path comparisons are stable
  export TD
  export XDG_CONFIG_HOME="$TD/cfg"
  export FAKE_STATE="$TD/fake"
  mkdir -p "$FAKE_STATE"
  export PATH="$SIMLANE_ROOT/tests/fakes:$PATH"
  unset CLAUDE_ENV_FILE FAKE_METRO_NEVER_READY FAKE_BUILD_EXIT FAKE_METRO_LINGER_SEC
}

source_libs() {   # load the library functions into the current shell (unit tests that bypass bin/simlane)
  local f
  for f in common lock worktree registry simulator metro deps app; do
    [ -f "$SIMLANE_ROOT/lib/$f.sh" ] && . "$SIMLANE_ROOT/lib/$f.sh"
  done
  for f in "$SIMLANE_ROOT"/lib/cmd/*.sh; do
    [ -f "$f" ] && . "$f"
  done
  return 0
}

make_repo() {   # DIR → a main checkout with .simlane.json, node_modules and one commit
  mkdir -p "$1"
  (
    cd "$1" \
      && git init -q -b main . \
      && git config user.email t@t.local && git config user.name t \
      && mkdir -p node_modules/pkg && echo '{}' > node_modules/pkg/package.json \
      && echo node_modules > .gitignore \
      && printf '%s\n' '{"ios":{"scheme":"App","bundleId":"com.example.app","buildCommand":"fake-build --udid {udid}"},"metro":{"startCommand":"fake-metro"}}' > .simlane.json \
      && echo 'console.log(1)' > index.js \
      && git add -A && git commit -qm init
  )
}

make_worktree() {   # REPO NAME → prints the worktree path
  ( cd "$1" && git worktree add -q --detach ".claude/worktrees/$2" HEAD 2>/dev/null )
  printf '%s\n' "$1/.claude/worktrees/$2"
}

make_brew_prefix() {   # DIR → a fake Homebrew prefix with simlane 0.2.0 installed the way the formula installs it
  local p=$1 c="$1/Cellar/simlane/0.2.0"
  mkdir -p "$c/libexec" "$c/bin" "$p/opt" "$p/bin"
  cp -R "$SIMLANE_ROOT/bin" "$SIMLANE_ROOT/lib" "$SIMLANE_ROOT/skills" "$SIMLANE_ROOT/VERSION" "$c/libexec/"
  ln -s ../libexec/bin/simlane "$c/bin/simlane"
  ln -s ../Cellar/simlane/0.2.0 "$p/opt/simlane"
  ln -s ../Cellar/simlane/0.2.0/bin/simlane "$p/bin/simlane"
}

# Under bash 3.2 (+bats) `set -e` ignores a failing [[ ]] on a non-final line, and `! cmd` is never an errexit trigger
# in any bash. A non-zero return from a function does trigger it, so assertions go through these helpers.
assert_contains()     { case "$1" in *"$2"*) return 0 ;; esac; echo "assert_contains failed: '$2' not in '$1'" >&2; return 1; }
assert_not_contains() { case "$1" in *"$2"*) echo "assert_not_contains failed: '$2' found in '$1'" >&2; return 1 ;; esac; return 0; }
assert_endswith()     { case "$1" in *"$2") return 0 ;; esac; echo "assert_endswith failed: '$1' does not end with '$2'" >&2; return 1; }
assert_fails()        { if "$@"; then echo "assert_fails failed: command succeeded: $*" >&2; return 1; fi; return 0; }
