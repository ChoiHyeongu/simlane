#!/usr/bin/env bash
# Prepare and push a release: scripts/release.sh X.Y.Z
# preconditions → tests → date CHANGELOG + write VERSION → commit + tag → confirm → push.
# The tag push starts .github/workflows/release.yml (GitHub Release + Homebrew tap).
set -euo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd -P)
fail() { echo "release: $*" >&2; exit 1; }

version_gt() {   # A B → success when X.Y.Z A is greater than B
  local IFS=.
  # shellcheck disable=SC2086  # split both versions on dots
  set -- $1 $2
  if [ "$1" -ne "$4" ]; then [ "$1" -gt "$4" ]; return; fi
  if [ "$2" -ne "$5" ]; then [ "$2" -gt "$5" ]; return; fi
  [ "$3" -gt "$6" ]
}

v=${1:-}
printf '%s\n' "$v" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || fail "usage: scripts/release.sh X.Y.Z"
root=$(git rev-parse --show-toplevel 2>/dev/null) || fail "not inside a git repository"
cd "$root"

# 1. preconditions — nothing is modified before all of them pass
[ "$(git symbolic-ref --short HEAD 2>/dev/null || true)" = main ] || fail "not on main"
[ -z "$(git status --porcelain)" ] || fail "working tree is not clean"
git fetch -q origin main --tags || fail "git fetch origin failed"
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || fail "main is not in sync with origin/main"
cur=0.0.0
if [ -f VERSION ]; then cur=$(tr -d '[:space:]' < VERSION); fi
version_gt "$v" "$cur" || fail "$v is not greater than the current version $cur"
if git rev-parse -q --verify "refs/tags/v$v" >/dev/null; then fail "tag v$v already exists"; fi
if git ls-remote --exit-code --tags origin "refs/tags/v$v" >/dev/null 2>&1; then fail "tag v$v already exists on origin"; fi
"$HERE/changelog-section.sh" Unreleased CHANGELOG.md >/dev/null || fail "CHANGELOG.md needs a non-empty '## Unreleased' section"

# 2. tests
echo "release: running tests" >&2
bash -c "${SIMLANE_RELEASE_TEST_CMD:-bats tests/}" || fail "tests failed"

# 3. CHANGELOG + VERSION
today=$(date +%Y-%m-%d)
awk -v v="$v" -v d="$today" '
  !done && /^## Unreleased[[:space:]]*$/ { print "## Unreleased"; print ""; print "## " v " — " d; done = 1; next }
  { print }
' CHANGELOG.md > CHANGELOG.md.tmp
cat CHANGELOG.md.tmp > CHANGELOG.md
rm -f CHANGELOG.md.tmp
printf '%s\n' "$v" > VERSION

# 4. commit + annotated tag
git add CHANGELOG.md VERSION
git commit -q -m "chore(release): $v"
git tag -a "v$v" -m "simlane $v"

# 5. confirm, push
printf 'release: push main and v%s to origin? [y/N] ' "$v" >&2
ans=
read -r ans || true
case "$ans" in
  y|Y|yes) ;;
  *) echo "release: not pushed. To undo: git tag -d v$v && git reset --hard HEAD~1" >&2; exit 0 ;;
esac
git push -q --atomic origin main "v$v" || fail "push failed; the commit and tag are still local"
echo "release: pushed v$v. CI publishes the GitHub Release and updates the tap: https://github.com/ChoiHyeongu/simlane/actions" >&2
